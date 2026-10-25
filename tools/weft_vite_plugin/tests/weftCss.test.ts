import {readdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';

import {
  build,
  createServer,
  type HotPayload,
  type InlineConfig,
  type ViteDevServer,
} from 'vite';
import {afterAll, afterEach, describe, expect, test} from 'vite-plus/test';

import {weftCss} from '../src/index.js';
import {sheetId} from '../src/internal/scan.js';
import {copyFixture, fixtureName, removeCopies} from './support.js';

afterAll(removeCopies);

const styled = fixtureName('styled');
const sheetOf = (file: string) => sheetId(`${styled}/src/${file}`);

/** A config for the client-only app at `root`, with `weftCss()` and no config file. */
function config(root: string): InlineConfig {
  return {
    root,
    configFile: false,
    logLevel: 'silent',
    plugins: [weftCss()],
    optimizeDeps: {noDiscovery: true, include: []},
  };
}

async function buildApp(root: string) {
  // A production build (Vitest sets `NODE_ENV` to `test`), unminified so the tests can read it.
  const nodeEnv = process.env.NODE_ENV;
  process.env.NODE_ENV = 'production';
  try {
    await build({...config(root), build: {minify: false, cssMinify: false}});
  } finally {
    process.env.NODE_ENV = nodeEnv;
  }
}

/** Every file in `dir`'s `assets`, by name, with its contents. */
function assets(root: string): Map<string, string> {
  const dir = join(root, 'dist/assets');
  return new Map(
    readdirSync(dir).map((name) => [
      name,
      readFileSync(join(dir, name), 'utf8'),
    ]),
  );
}

/** Replaces `from` with `to` in a compiled file of the copy at `root`, as `rescript build` would. */
function rewrite(root: string, file: string, from: string, to: string) {
  const path = join(root, file);
  const code = readFileSync(path, 'utf8');
  expect(code).toContain(from);
  writeFileSync(path, code.replace(from, to));
  return path;
}

describe('a build with weftCss()', () => {
  let files: Map<string, string>;
  const css = () => [...files].filter(([name]) => name.endsWith('.css'));
  const js = () => [...files].filter(([name]) => name.endsWith('.js'));

  test('builds', async () => {
    const root = copyFixture('styled');
    await buildApp(root);
    files = assets(root);
    // The page links the entry's CSS, as for any CSS a module imports.
    expect(readFileSync(join(root, 'dist/index.html'), 'utf8')).toMatch(
      /<link rel="stylesheet" crossorigin href="\/assets\/[^"]+\.css">/,
    );
  });

  test("puts each file's sheet with its module's chunk: the entry's, and the lazy one's", () => {
    const [entry, lazy] = [
      css().find(([, text]) => text.includes('.Card-Styles-card_')),
      css().find(([, text]) => text.includes('.Later-later_')),
    ];
    expect(entry).toBeDefined();
    expect(lazy).toBeDefined();
    expect(entry![0]).not.toBe(lazy![0]);
    expect(entry![1]).not.toContain('.Later-later_');
    const card = sheetOf('Card.res');
    const theme = sheetOf('Theme.res');
    expect(entry![1]).toContain(`--Theme-ink_${theme}: #1d1b19;`);
    expect(entry![1]).toContain(`color: var(--Theme-ink_${theme});`);
    expect(entry![1]).toContain(`@keyframes Card-fadeIn_${card}`);
    expect(entry![1]).toContain(`.Card-Styles-card_${card}:hover {`);
    expect(entry![1]).toContain('@layer weft.components');
  });

  test("leaves the definitions, and weft_css's serializer, out of the JavaScript", () => {
    for (const [name, text] of js()) {
      expect(text, name).not.toContain('DEFINITION_SENTINEL_CARD');
      expect(text, name).not.toContain('grid-template-columns');
      expect(text, name).not.toContain('Internal.class_');
    }
    // But the names are there, as the strings the modules export.
    expect(
      js().some(([, text]) =>
        text.includes(`"Card-Styles-card_${sheetOf('Card.res')}"`),
      ),
    ).toBe(true);
  });
});

describe('a build that fails', () => {
  test('names a definition that throws', async () => {
    const root = copyFixture('styled');
    rewrite(
      root,
      'src/Card.res.js',
      'newrecord.content = "\\"DEFINITION_SENTINEL_CARD\\"";',
      'newrecord.content = (() => { throw new Error("boom"); })();',
    );
    await expect(buildApp(root)).rejects.toThrow(
      `[weft] weft_css: the definition of Card-Styles-card_${sheetOf('Card.res')} threw: boom`,
    );
  });

  test('names a style file whose top level needs the browser', async () => {
    const root = copyFixture('styled');
    rewrite(
      root,
      'src/Theme.res.js',
      'let ink =',
      'document.title;\nlet ink =',
    );
    // Card, which imports Theme, is first.
    await expect(buildApp(root)).rejects.toThrow(
      `[weft] couldn't extract the styles of ${styled}/src/Card.res: importing it (or a file it imports) threw document is not defined.`,
    );
  });

  test("says so when the app doesn't run ppx_weft", async () => {
    const root = copyFixture('styled');
    const path = join(root, 'rescript.json');
    writeFileSync(
      path,
      JSON.stringify({
        ...JSON.parse(readFileSync(path, 'utf8')),
        'ppx-flags': [],
      }),
    );
    await expect(buildApp(root)).rejects.toThrow(/doesn't run ppx_weft/);
  });
});

describe('a dev server with weftCss()', () => {
  let server: ViteDevServer | undefined;
  afterEach(async () => {
    await server?.close();
    server = undefined;
  });

  async function start(root: string) {
    server = await createServer({
      ...config(root),
      server: {middlewareMode: true, watch: null, ws: false},
    });
    return server;
  }

  test('serves a style file stripped, importing its sheet, and the sheet as CSS', async () => {
    const root = copyFixture('styled');
    const server = await start(root);
    const card = sheetOf('Card.res');
    const module = await server.transformRequest('/src/Card.res.js');
    expect(module!.code).toContain(`/node_modules/.weft-css/${card}.css`);
    expect(module!.code).not.toContain('DEFINITION_SENTINEL_CARD');
    const sheet = await server.transformRequest(
      `/node_modules/.weft-css/${card}.css`,
    );
    expect(sheet!.code).toContain(`.Card-Styles-card_${card}:hover`);
  });

  test('extracts a style file again when ReScript rewrites it', async () => {
    const root = copyFixture('styled');
    const server = await start(root);
    const card = sheetOf('Card.res');
    const url = `/node_modules/.weft-css/${card}.css`;
    expect((await server.transformRequest(url))!.code).toContain(
      'opacity: 0.9',
    );
    const path = rewrite(
      root,
      'src/Card.res.js',
      'opacity: 0.9',
      'opacity: 0.5',
    );
    server.watcher.emit('change', path);
    let code = '';
    for (let i = 0; i < 100 && !code.includes('opacity: 0.5'); i++) {
      await new Promise((done) => setTimeout(done, 20));
      code = (await server.transformRequest(url))!.code;
    }
    expect(code).toContain('opacity: 0.5');
    expect(code).not.toContain('opacity: 0.9');
  });
});

describe('a dev server with weftCss(), when only CSS changes', () => {
  let server: ViteDevServer | undefined;
  afterEach(async () => {
    await server?.close();
    server = undefined;
  });

  test('updates the sheet as Vite updates CSS, with no reload; a code change reloads', async () => {
    const root = copyFixture('styled');
    server = await createServer({
      ...config(root),
      server: {middlewareMode: true, watch: null, ws: false},
    });
    const client = server.environments.client!;
    const sent: HotPayload[] = [];
    const send = client.hot.send.bind(client.hot);
    client.hot.send = ((payload: HotPayload) => {
      sent.push(payload);
      send(payload);
    }) as typeof client.hot.send;
    const card = sheetOf('Card.res');
    // The page has the module, and so its sheet.
    await client.transformRequest('/src/Card.res.js');
    await client.transformRequest(`/node_modules/.weft-css/${card}.css`);
    const wait = async () => {
      for (let i = 0; i < 100 && sent.length === 0; i++) {
        await new Promise((done) => setTimeout(done, 10));
      }
    };
    server.watcher.emit(
      'change',
      rewrite(root, 'src/Card.res.js', 'opacity: 0.9', 'opacity: 0.4'),
    );
    await wait();
    expect(sent.map((payload) => payload.type)).toEqual(['update']);
    const [update] = sent as [Extract<HotPayload, {type: 'update'}>];
    expect(update.updates.map(({path}) => path)).toEqual([
      `/node_modules/.weft-css/${card}.css`,
    ]);
    // A change to the code (a class added) reloads, as any change to a ReScript module does.
    sent.length = 0;
    server.watcher.emit(
      'change',
      rewrite(
        root,
        'src/Card.res.js',
        'export {',
        `let extra = Css$WeftCss.Internal.class_("Card-extra_${card}", undefined, () => ({}));\n\nexport {\n  extra,`,
      ),
    );
    await wait();
    expect(sent.map((payload) => payload.type)).toEqual(['full-reload']);
  });
});
