import {
  copyFileSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import type {AddressInfo} from 'node:net';
import {join} from 'node:path';

import {createServer, type HotPayload, type ViteDevServer} from 'vite';
import {
  afterAll,
  afterEach,
  beforeEach,
  describe,
  expect,
  test,
} from 'vite-plus/test';

import {clientEnvironment, serverEnvironment} from '../src/index.js';
import {
  config,
  copyFixture,
  fixtureName,
  fixtures,
  removeCopies,
} from './support.js';

afterAll(removeCopies);

let root: string;
let server: ViteDevServer;
let base: string;
/** What the plugin and Vite sent on each environment's HMR channel. */
let sent: Record<string, HotPayload[]>;

const basic = fixtureName('basic');
const widgets = fixtureName('widgets');

/** `src/Later.res.js`'s compiled code, set aside before the server starts (see its test). */
const later = '.later.res.js';

async function start(fixture: string) {
  root = copyFixture(fixture);
  if (fixture === 'basic') {
    renameSync(join(root, 'src/Later.res.js'), join(root, later));
  }
  server = await createServer({
    ...config(root),
    server: {host: '127.0.0.1', port: 0, ws: false},
  });
  // This server's own record: one closed after its test can still send something.
  const record: Record<string, HotPayload[]> = {};
  sent = record;
  for (const name of [clientEnvironment, serverEnvironment]) {
    const hot = server.environments[name]!.hot;
    const send = hot.send.bind(hot);
    record[name] = [];
    hot.send = ((payload: HotPayload) => {
      record[name]!.push(payload);
      send(payload);
    }) as typeof hot.send;
  }
  await server.listen();
  base = `http://127.0.0.1:${(server.httpServer!.address() as AddressInfo).port}`;
}

afterEach(async () => {
  await server?.close();
});

/** Waits (a while, at most) for something to be sent to the client: Vite handles changes later. */
async function clientMessage() {
  for (let i = 0; i < 100 && sent[clientEnvironment]!.length === 0; i++) {
    await new Promise((done) => setTimeout(done, 10));
  }
}

/**
 * Has `file` (from the root) written again, as `rescript build -w` does when its source (or one it
 * depends on) changes, and has Vite see it now. The code is the same: what's being tested is what's
 * sent, and that the module runs again.
 */
async function rewrite(file: string) {
  const path = join(root, file);
  writeFileSync(path, readFileSync(path, 'utf8'));
  server.watcher.emit('change', path);
  await clientMessage();
}

/** The value the server's `Notes` module had when it last ran. */
async function notesInstance() {
  const html = await (await fetch(`${base}/notes/1`)).text();
  return html.match(/<p id="instance">([^<]*)<\/p>/)![1];
}

const events = (name: string) =>
  sent[name]!.map((payload) =>
    payload.type === 'custom'
      ? `${payload.event} ${JSON.stringify(payload.data)}`
      : payload.type,
  );

describe('the dev server', () => {
  beforeEach(() => start('basic'));

  test('answers a page with the server entry, and the assets point at the source', async () => {
    const response = await fetch(`${base}/notes/1`);
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('text/html');
    const html = await response.text();
    expect(html).toContain('Notes at /notes/1');
    expect(html).toContain(
      '<script type="module" src="/@vite/client"></script>',
    );
    expect(html).toContain(
      '<script type="module" src="/src/Client.res.js"></script>',
    );
    // An entrypoint the server imports has its mark.
    expect(html).toContain(`${basic}/src/Likes.res#`);
  });

  test('answers a payload request with the payload', async () => {
    const response = await fetch(`${base}/notes/2`, {
      headers: {Accept: 'text/x-weft-payload'},
    });
    expect(response.headers.get('content-type')).toBe('text/x-weft-payload');
    expect(await response.text()).toBe('0:J"Notes at /notes/2 (20)"\n');
  });

  test('lists each entrypoint file in the assets, as the dev server serves it', async () => {
    const assets = await (await fetch(`${base}/assets.json`)).json();
    expect(assets.entrypoints).toEqual({
      [`${basic}/src/Likes.res`]: ['/src/Likes.res.js'],
      [`${basic}/src/Panels.res`]: ['/src/Panels.res.js'],
      [`${basic}/src/nested/Deep.res`]: ['/src/nested/Deep.res.js'],
      [`${widgets}/src/Widget.res`]: [
        `/@fs${join(fixtures, 'widgets/src/Widget.res.js')}`,
      ],
    });
  });

  test('runs the server with the development export conditions', async () => {
    expect(await (await fetch(`${base}/env`)).json()).toEqual({isDev: true});
  });

  test('serves the client its references, and the files without their directives', async () => {
    const client = server.environments[clientEnvironment]!;
    const references = await client.transformRequest(
      'virtual:weft/client-references',
    );
    for (const file of [
      'src/Likes.res.js',
      'src/Panels.res.js',
      'src/nested/Deep.res.js',
    ]) {
      expect(references?.code).toContain(`import("/${file}")`);
    }
    expect(references?.code).toContain(`"${widgets}/src/Widget.res"`);
    const likes = await client.transformRequest('/src/Likes.res.js');
    expect(likes?.code).not.toContain('use weft');
    expect(likes?.code).toContain(`${basic}/src/Likes.res#`);
  });

  test('refuses a server file to the client', async () => {
    await expect(
      server.environments[clientEnvironment]!.transformRequest(
        '/src/Notes.res.js',
      ),
    ).rejects.toThrow(
      "[weft] src/Notes.res.js is a server file ('use weft server': it has server components, " +
        "or @@weft.server), so the client can't import it, but it does: src/Notes.res.js.",
    );
  });

  test('keeps the server virtual modules from the client, and the client ones from the server', async () => {
    await expect(
      server.environments[clientEnvironment]!.transformRequest(
        'virtual:weft/assets',
      ),
    ).rejects.toThrow('virtual:weft/assets is only for the server');
    await expect(
      server.environments[serverEnvironment]!.transformRequest(
        'virtual:weft/client',
      ),
    ).rejects.toThrow('virtual:weft/client is only for the client');
  });

  test('sends the refresh event when a file only the server has changes, and runs it again', async () => {
    const before = await notesInstance();
    await server.environments[clientEnvironment]!.transformRequest(
      '/src/Likes.res.js',
    );
    await rewrite('src/Notes.res.js');
    expect(events(clientEnvironment)).toEqual([
      'weft:refresh {"file":"src/Notes.res.js"}',
    ]);
    expect(await notesInstance()).not.toBe(before);
  });

  test('reloads the page when an entrypoint file changes', async () => {
    await fetch(`${base}/notes/1`);
    await server.environments[clientEnvironment]!.transformRequest(
      '/src/Likes.res.js',
    );
    await rewrite('src/Likes.res.js');
    expect(events(clientEnvironment)).toEqual(['full-reload']);
  });

  test('updates the references, and reloads, when an entrypoint file appears', async () => {
    const client = server.environments[clientEnvironment]!;
    const before = await client.transformRequest(
      'virtual:weft/client-references',
    );
    expect(before?.code).not.toContain('Later.res');
    const path = join(root, 'src/Later.res.js');
    renameSync(join(root, later), path);
    server.watcher.emit('add', path);
    await clientMessage();
    expect(events(clientEnvironment)).toEqual(['full-reload']);
    const after = await client.transformRequest(
      'virtual:weft/client-references',
    );
    expect(after?.code).toContain(`"${basic}/src/Later.res"`);
  });

  test('updates the references, and reloads, when an entrypoint file is deleted', async () => {
    const client = server.environments[clientEnvironment]!;
    await client.transformRequest('virtual:weft/client-references');
    const path = join(root, 'src/nested/Deep.res.js');
    rmSync(path);
    server.watcher.emit('unlink', path);
    await clientMessage();
    expect(events(clientEnvironment)).toEqual(['full-reload']);
    const references = await client.transformRequest(
      'virtual:weft/client-references',
    );
    expect(references?.code).not.toContain('Deep.res');
  });
});

describe("weft_server's own server-only modules", () => {
  test("are refused to the client, as an app's server files are; the shared ones are not", async () => {
    const root = copyFixture('basic');
    // The copy is in a temporary directory, and weft_server outside it: let the dev server serve it.
    const vite = await createServer({
      ...config(root),
      server: {fs: {strict: false}},
    });
    try {
      const client = vite.environments[clientEnvironment]!;
      const file = (path: string) =>
        realpathSync(join(root, 'node_modules/@e-cline/weft_server/src', path));
      // `Render`, `Page` and `RpcServer` are marked server-only.
      for (const path of [
        'server/Render.res.js',
        'server/Page.res.js',
        'server/RpcServer.res.js',
      ]) {
        await expect(client.transformRequest(file(path))).rejects.toThrow(
          /is a server file \('use weft server'.*so the client can't import it/,
        );
      }
      for (const path of [
        'shared/Rpc.res.js',
        'shared/Decoder.res.js',
        'client/Bootstrap.res.js',
      ]) {
        await expect(client.transformRequest(file(path))).resolves.toBeTruthy();
      }
    } finally {
      await vite.close();
    }
  });
});

describe('the dev server, with an RPC ID declared twice', () => {
  test("doesn't start, naming both files", async () => {
    const root = copyFixture('basic');
    copyFileSync(join(root, 'src/Api.res.js'), join(root, 'src/Again.res.js'));
    await expect(createServer(config(root))).rejects.toThrow(
      `the RPC ID basic.save is declared twice: in ${basic}/src/Again.res and in ${basic}/src/Api.res`,
    );
  });
});

describe('the dev server, with a client importing a server file', () => {
  beforeEach(() => start('client_imports_server'));

  test('fails the request for it, naming the chain of imports', async () => {
    const client = server.environments[clientEnvironment]!;
    await client.transformRequest('/src/Client.res.js');
    await client.transformRequest('/src/Helpers.res.js');
    await expect(client.transformRequest('/src/Db.res.js')).rejects.toThrow(
      'but it does: src/Client.res.js -> src/Helpers.res.js -> src/Db.res.js.',
    );
  });
});
