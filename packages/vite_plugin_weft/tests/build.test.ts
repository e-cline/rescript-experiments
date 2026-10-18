import {existsSync, readdirSync, readFileSync, writeFileSync} from 'node:fs';
import type {AddressInfo} from 'node:net';
import {join} from 'node:path';

import {createBuilder} from 'vite';
import {afterAll, beforeAll, describe, expect, test} from 'vite-plus/test';

import type {Manifest} from '../src/internal/virtualModules.js';
import {serve} from '../src/node.js';
import {config, copyFixture, removeCopies} from './support.js';

afterAll(removeCopies);

async function buildApp(root: string) {
  // Vite takes a production build to be one with `NODE_ENV` unset or `production`, and Vitest sets
  // it to `test`, which would build with the development export conditions.
  const nodeEnv = process.env.NODE_ENV;
  process.env.NODE_ENV = 'production';
  try {
    // Unminified, so the tests can look for functions by name.
    const builder = await createBuilder({
      ...config(root),
      build: {minify: false},
    });
    await builder.buildApp();
  } finally {
    process.env.NODE_ENV = nodeEnv;
  }
}

/** Every file under `dir`, as paths from it. */
function filesUnder(dir: string): string[] {
  return readdirSync(dir, {recursive: true, withFileTypes: true})
    .filter((entry) => entry.isFile())
    .map((entry) => join(entry.parentPath, entry.name).slice(dir.length + 1));
}

describe('a build of the basic fixture', () => {
  let root: string;
  let manifest: Manifest;
  let clientDir: string;
  const chunkOf = (key: string) =>
    readFileSync(join(clientDir, manifest[key]!.file), 'utf8');

  beforeAll(async () => {
    root = copyFixture('basic');
    await buildApp(root);
    clientDir = join(root, 'dist/client');
    manifest = JSON.parse(
      readFileSync(join(clientDir, '.vite/manifest.json'), 'utf8'),
    );
  });

  test('has the bootstrap as the only entry, and each entrypoint file as a chunk of its own', () => {
    expect(manifest['src/Client.res.js']?.isEntry).toBe(true);
    const entrypointFiles = [
      'src/Likes.res.js',
      'src/Panels.res.js',
      'src/nested/Deep.res.js',
      'widgets/src/Widget.res.js',
    ];
    for (const key of entrypointFiles)
      expect(manifest[key]?.isDynamicEntry, key).toBe(true);
    const chunks = entrypointFiles.map((key) => manifest[key]!.file);
    expect(new Set(chunks).size).toBe(entrypointFiles.length);
    expect(
      Object.values(manifest).filter((chunk) => chunk.isEntry),
    ).toHaveLength(1);
  });

  test("puts the shared module in a chunk the entrypoints import, not in either's", () => {
    const likes = manifest['src/Likes.res.js']!;
    const panels = manifest['src/Panels.res.js']!;
    const shared = (likes.imports ?? []).filter((key) =>
      panels.imports?.includes(key),
    );
    expect(shared).not.toHaveLength(0);
    const sharedCode = shared.map((key) =>
      readFileSync(join(clientDir, manifest[key]!.file), 'utf8'),
    );
    expect(sharedCode.join('')).toContain('function label(');
    expect(chunkOf('src/Likes.res.js')).not.toContain('function label(');
    expect(chunkOf('src/Panels.res.js')).not.toContain('function label(');
  });

  test('keeps the large client-only module in the chunk of the one entrypoint using it', () => {
    const holding = filesUnder(clientDir).filter((file) =>
      readFileSync(join(clientDir, file), 'utf8').includes(
        'CLIENT_SENTINEL_91c2',
      ),
    );
    expect(holding).toEqual([manifest['src/Panels.res.js']!.file]);
  });

  test('has no server code in the client', () => {
    for (const file of filesUnder(clientDir)) {
      const code = readFileSync(join(clientDir, file), 'utf8');
      expect(code, file).not.toContain('SERVER_SENTINEL_7f3a');
      expect(code, file).not.toContain('use weft');
    }
  });

  test('keeps the export names the client walks to, `$$Error` included', () => {
    const panels = chunkOf('src/Panels.res.js');
    expect(panels).toMatch(/\$\$Error/);
    expect(panels).toMatch(/Tabs/);
  });

  test('writes the server as dist/server/index.js, with the assets from the manifest', async () => {
    const serverFile = join(root, 'dist/server/index.js');
    expect(existsSync(serverFile)).toBe(true);
    const server = readFileSync(serverFile, 'utf8');
    expect(server).not.toContain('use weft');
    expect(server).toContain(manifest['src/Client.res.js']!.file);
    const handler = (await import(serverFile)) as {
      default: (request: Request) => Promise<Response>;
    };
    const assets = await (
      await handler.default(new Request('http://localhost/assets.json'))
    ).json();
    expect(assets.scripts).toEqual(['/' + manifest['src/Client.res.js']!.file]);
    expect(assets.entrypoints['@fixtures/basic/src/Panels.res'][0]).toBe(
      '/' + manifest['src/Panels.res.js']!.file,
    );
    expect(Object.keys(assets.entrypoints).sort()).toEqual([
      '@fixtures/basic/src/Likes.res',
      '@fixtures/basic/src/Panels.res',
      '@fixtures/basic/src/nested/Deep.res',
      '@fixtures/widgets/src/Widget.res',
    ]);
  });

  test('runs the production build of the server', async () => {
    const handler = (await import(join(root, 'dist/server/index.js'))) as {
      default: (request: Request) => Promise<Response>;
    };
    expect(
      await (await handler.default(new Request('http://localhost/env'))).json(),
    ).toEqual({
      isDev: false,
    });
  });

  test('is served by `serve`: the static files, then the handler', async () => {
    const server = await serve({dir: join(root, 'dist'), port: 0});
    try {
      const {port} = server.address() as AddressInfo;
      const base = `http://127.0.0.1:${port}`;
      const page = await fetch(`${base}/notes`);
      expect(page.headers.get('content-type')).toContain('text/html');
      const html = await page.text();
      expect(html).toContain('Notes at /notes');
      const script = html.match(/src="([^"]+)"/)![1]!;
      const js = await fetch(base + script);
      expect(js.status).toBe(200);
      expect(js.headers.get('content-type')).toContain('text/javascript');
      expect(js.headers.get('cache-control')).toContain('immutable');
      expect(await js.text()).toContain('__weftLoadModule');
      // The build's manifest isn't the app's, and nothing outside the client's files is served.
      expect(
        (await fetch(`${base}/.vite/manifest.json`)).headers.get(
          'content-type',
        ),
      ).toContain('text/html');
      expect(
        await (await fetch(`${base}/..%2Fserver%2Findex.js`)).text(),
      ).toContain('Notes at');
    } finally {
      await new Promise((done) => server.close(done));
    }
  });
});

describe('building a fixture whose client imports a server file', () => {
  test('fails, naming the chain of imports', async () => {
    const root = copyFixture('client-imports-server');
    await expect(buildApp(root)).rejects.toThrow(
      "src/Db.res.js has server components ('use weft server'), so the client can't import it, " +
        'but it does: src/Client.res.js -> src/Helpers.res.js -> src/Db.res.js',
    );
  });
});

describe('building without ppx_weft', () => {
  test('fails, saying how to set it up', async () => {
    const root = copyFixture('basic');
    const rescriptJson = JSON.parse(
      readFileSync(join(root, 'rescript.json'), 'utf8'),
    );
    delete rescriptJson['ppx-flags'];
    writeFileSync(join(root, 'rescript.json'), JSON.stringify(rescriptJson));
    await expect(buildApp(root)).rejects.toThrow(
      /doesn't run ppx_weft: add "@e-cline\/ppx_weft\/ppx"/,
    );
  });
});
