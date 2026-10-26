import {
  copyFileSync,
  mkdirSync,
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
import {sheetId} from '../src/internal/scan.js';
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
    // No file watching: each test tells the watcher what changed (`rewrite`, and `emit` for files
    // added and removed). With it on, the change's own event comes too, at a time that depends on
    // the platform (soon enough on Linux to be a second message), so what's sent wouldn't be fixed.
    server: {host: '127.0.0.1', port: 0, ws: false, watch: null},
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

  test('lists each sheet in the assets, at a URL the dev server serves it as CSS from', async () => {
    const assets = await (await fetch(`${base}/assets.json`)).json();
    const notes = sheetId(`${basic}/src/Notes.res`);
    const theme = sheetId(`${basic}/src/Theme.res`);
    expect(assets.sheets[notes]).toEqual({
      href: `/node_modules/.weft-css/${notes}.css`,
      dependencies: [theme],
    });
    expect(assets.entrypointSheets[`${basic}/src/Likes.res`]).toEqual([theme]);
    // As a page's <link> asks for it.
    const response = await fetch(`${base}${assets.sheets[notes].href}`, {
      headers: {Accept: 'text/css,*/*;q=0.1'},
    });
    expect(response.headers.get('content-type')).toMatch(/^text\/css/);
    expect(await response.text()).toContain(`.Notes-heading_${notes} {`);
  });

  test("has the client's import() of a style module wait for its sheets too; not the server's", async () => {
    const assets = await (await fetch(`${base}/assets.json`)).json();
    const popover = sheetId(`${basic}/src/Popover.res`);
    const theme = sheetId(`${basic}/src/Theme.res`);
    const likes =
      await server.environments[clientEnvironment]!.transformRequest(
        '/src/Likes.res.js',
      );
    // Popover's sheet, and the one it depends on (Theme's variable) first, at the URLs the server
    // sends: the import resolves once they've loaded.
    expect(likes?.code).toContain(
      `__weftImport(import("/src/Popover.res.js"), [${JSON.stringify(assets.sheets[theme].href)}, ${JSON.stringify(assets.sheets[popover].href)}])`,
    );
    // Popover itself runs as it is.
    const popoverCode = await server.environments[
      clientEnvironment
    ]!.transformRequest('/src/Popover.res.js');
    expect(popoverCode?.code).not.toContain('__weft');
    const onServer =
      await server.environments[serverEnvironment]!.transformRequest(
        '/src/Likes.res.js',
      );
    expect(onServer?.code).not.toContain('__weftImport');
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

  test('gives the server its own reference map, and the assets its loadModule', async () => {
    const assets = await server.environments[
      serverEnvironment
    ]!.transformRequest('virtual:weft/assets');
    expect(assets?.code).toContain('virtual:weft/ssr-references');
    const references = await server.environments[
      serverEnvironment
    ]!.transformRequest('virtual:weft/ssr-references');
    expect(references?.code).toContain(`"${basic}/src/Likes.res"`);
  });

  test('keeps the server virtual modules from the client, and the client ones from the server', async () => {
    await expect(
      server.environments[clientEnvironment]!.transformRequest(
        'virtual:weft/assets',
      ),
    ).rejects.toThrow('virtual:weft/assets is only for the server');
    await expect(
      server.environments[clientEnvironment]!.transformRequest(
        'virtual:weft/ssr-references',
      ),
    ).rejects.toThrow('virtual:weft/ssr-references is only for the server');
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

  test('swaps a sheet in place, with no reload or refetch, when only a definition changes', async () => {
    // The sheets are extracted once the assets are first asked for (the first page).
    await fetch(`${base}/assets.json`);
    await server.environments[clientEnvironment]!.transformRequest(
      '/src/Likes.res.js',
    );
    const theme = sheetId(`${basic}/src/Theme.res`);
    const path = join(root, 'src/Theme.res.js');
    writeFileSync(
      path,
      readFileSync(path, 'utf8').replace(
        'content: "\\"DEFINITION_SENTINEL_THEME\\""',
        'opacity: 0.5',
      ),
    );
    // ReScript writes a copy in its `lib/` too, whose change is handled at the same time.
    const copy = join(root, 'lib/bs/src/Theme.res.js');
    mkdirSync(join(root, 'lib/bs/src'), {recursive: true});
    copyFileSync(path, copy);
    server.watcher.emit('change', path);
    server.watcher.emit('change', copy);
    await clientMessage();
    expect(events(clientEnvironment)).toEqual([
      `weft:css {"id":"${theme}","href":"/node_modules/.weft-css/${theme}.css"}`,
    ]);
    // Nor does the server's module runner reload the file (its code is the same).
    expect(
      events(serverEnvironment).filter(
        (event) => !event.startsWith('vite:invoke'),
      ),
    ).toEqual([]);
    // The dev server serves the new CSS (the client asks for it with a new query).
    const css = await (
      await fetch(`${base}/node_modules/.weft-css/${theme}.css?t=1`, {
        headers: {Accept: 'text/css'},
      })
    ).text();
    expect(css).toContain('opacity: 0.5');
  });

  test('extracts a sheet again when a file its definitions use changes, though it has no styles', async () => {
    await fetch(`${base}/assets.json`);
    await server.environments[clientEnvironment]!.transformRequest(
      '/src/Likes.res.js',
    );
    const theme = sheetId(`${basic}/src/Theme.res`);
    const path = join(root, 'src/Colors.res.js');
    writeFileSync(
      path,
      readFileSync(path, 'utf8').replace('"#1d1b19"', '"#123456"'),
    );
    server.watcher.emit('change', path);
    await clientMessage();
    // `Colors` is the server's and the client's too: handled as usual, and Theme's link swapped.
    expect(events(clientEnvironment)).toContain(
      `weft:css {"id":"${theme}","href":"/node_modules/.weft-css/${theme}.css"}`,
    );
    const css = await (
      await fetch(`${base}/node_modules/.weft-css/${theme}.css?t=1`, {
        headers: {Accept: 'text/css'},
      })
    ).text();
    expect(css).toContain(`--Theme-ink_${theme}: #123456;`);
  });

  test('extracts the sheets again once a definition that threw is fixed', async () => {
    const theme = sheetId(`${basic}/src/Theme.res`);
    const path = join(root, 'src/Theme.res.js');
    const code = readFileSync(path, 'utf8');
    writeFileSync(
      path,
      code.replace(
        'content: "\\"DEFINITION_SENTINEL_THEME\\""',
        'content: (() => { throw new Error("boom"); })()',
      ),
    );
    const sheet = () =>
      fetch(`${base}/node_modules/.weft-css/${theme}.css`, {
        headers: {Accept: 'text/css'},
      });
    expect((await sheet()).status).toBe(500);
    writeFileSync(path, code);
    server.watcher.emit('change', path);
    await clientMessage();
    const fixed = await sheet();
    expect(fixed.status).toBe(200);
    expect(await fixed.text()).toContain(`--Theme-ink_${theme}: #1d1b19;`);
  });

  test('reloads as usual when a style is added, which changes the code too', async () => {
    await fetch(`${base}/assets.json`);
    await server.environments[clientEnvironment]!.transformRequest(
      '/src/Likes.res.js',
    );
    const theme = sheetId(`${basic}/src/Theme.res`);
    const path = join(root, 'src/Theme.res.js');
    writeFileSync(
      path,
      readFileSync(path, 'utf8').replace(
        'export {',
        `let extra = Css$WeftCss.Internal.class_("Theme-extra_${theme}", undefined, () => ({}));\n\nexport {\n  extra,`,
      ),
    );
    server.watcher.emit('change', path);
    await clientMessage();
    expect(events(clientEnvironment)).toEqual(['full-reload']);
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

describe("Weft's own server-only modules", () => {
  test("are refused to the client, as an app's server files are; the shared ones are not", async () => {
    const root = copyFixture('basic');
    // The copy is in a temporary directory, and Weft's packages outside it: let the dev server serve them.
    const vite = await createServer({
      ...config(root),
      server: {fs: {strict: false}},
    });
    try {
      const client = vite.environments[clientEnvironment]!;
      const file = (path: string) =>
        realpathSync(join(root, 'node_modules/@e-cline', path));
      // weft_server's `Render`, `Page` and `RpcServer`, and weft_dom's `Html`, are server-only.
      for (const path of [
        'weft_server/src/server/Render.res.js',
        'weft_server/src/server/Page.res.js',
        'weft_server/src/server/RpcServer.res.js',
        'weft_dom/src/server/Html.res.js',
      ]) {
        await expect(client.transformRequest(file(path))).rejects.toThrow(
          /is a server file \('use weft server'.*so the client can't import it/,
        );
      }
      for (const path of [
        'weft_server/src/shared/Rpc.res.js',
        'weft_server/src/shared/Decoder.res.js',
        'weft_server/src/client/Bootstrap.res.js',
        'weft_dom/src/shared/DomProps.res.js',
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
