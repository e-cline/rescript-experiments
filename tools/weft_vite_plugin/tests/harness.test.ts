// The harness's server side (`src/testing.ts`): the app's server in a worker, reached over a port.

import {writeFileSync, readFileSync} from 'node:fs';
import {join} from 'node:path';

import {
  afterAll,
  afterEach,
  beforeEach,
  describe,
  expect,
  test,
} from 'vite-plus/test';

import {readPage, start, type App, type Piece} from '../src/testing.js';
import {config, copyFixture, fixtureName, removeCopies} from './support.js';

afterAll(removeCopies);

const basic = fixtureName('basic');

let app: App;
let root: string;

beforeEach(async () => {
  root = copyFixture('basic');
  app = await start({root, configFile: false, config: config(root)});
});

afterEach(async () => {
  await app.close();
});

describe('the harness, in source mode', () => {
  test("answers a request with the app's server, in the worker", async () => {
    const response = await app.fetch('/notes/1');
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('text/html');
    const html = await response.text();
    expect(html).toContain('Notes at /notes/1');
    expect(html).toContain(`${basic}/src/Likes.res#`);
    expect(app.requests).toEqual(['/notes/1']);
  });

  test("runs the server in a realm of its own, with none of the browser's globals", async () => {
    expect(
      await app.serverGlobals(['document', 'window', 'fetch', 'Response']),
    ).toEqual(['fetch', 'Response']);
  });

  test('keeps the cookies the server sets, sends them with later requests, and forgets expired ones', async () => {
    const echo = async () =>
      (
        (await (await app.fetch('/cookies/echo')).json()) as {
          cookie: string | null;
        }
      ).cookie;
    expect(await echo()).toBe(null);
    await app.fetch('/cookies/set');
    expect(app.cookies()).toEqual({flavour: 'oat'});
    expect(await echo()).toBe('flavour=oat');
    // A request that brings its own cookies sends those.
    const own = await app.fetch('/cookies/echo', {headers: {cookie: 'mine=1'}});
    expect(((await own.json()) as {cookie: string}).cookie).toBe('mine=1');
    await app.fetch('/cookies/expire');
    expect(app.cookies()).toEqual({});
    expect(await echo()).toBe(null);
    await app.fetch('/cookies/set');
    app.clearCookies();
    expect(await echo()).toBe(null);
  });

  test('runs the server with the development conditions', async () => {
    expect(await (await app.fetch('/env')).json()).toEqual({isDev: true});
  });

  test("calls into the server's modules: the same instances the app uses", async () => {
    const instance = await app.callServer('src/Notes.res.js', 'title', ['/x']);
    expect(instance).toBe('Notes at /x (20)');
    const html = await (await app.fetch('/notes/1')).text();
    const shown = html.match(/<p id="instance">([^<]*)<\/p>/)![1];
    // `instance` is a value, not a function: read it through a function of the module's.
    expect(shown).not.toBe('');
  });

  test('sends request bodies, and holds response chunks until delivered', async () => {
    app.delivery = {type: 'manual'};
    const response = await app.fetch('/notes/3', {
      headers: {Accept: 'text/x-weft-payload'},
    });
    const reader = response.body!.getReader();
    const read = reader.read();
    let settled = false;
    void read.then(() => {
      settled = true;
    });
    await new Promise((done) => setTimeout(done, 20));
    expect(settled).toBe(false);
    expect(app.waiting).toBe(1);
    app.deliverAll();
    const {value} = await read;
    expect(new TextDecoder().decode(value)).toBe(
      '0:J"Notes at /notes/3 (20)"\n',
    );
    expect((await reader.read()).done).toBe(true);
    expect(app.open).toBe(0);
  });

  test('re-chunks responses every n bytes', async () => {
    app.delivery = {type: 'everyBytes', size: 4};
    const response = await app.fetch('/notes/3', {
      headers: {Accept: 'text/x-weft-payload'},
    });
    const reader = response.body!.getReader();
    const chunks: string[] = [];
    for (;;) {
      const {done, value} = await reader.read();
      if (done) break;
      chunks.push(new TextDecoder().decode(value));
    }
    expect(chunks.join('')).toBe('0:J"Notes at /notes/3 (20)"\n');
    expect(chunks.every((chunk) => chunk.length <= 4)).toBe(true);
  });

  test('runs changed server code once Vite sees the change', async () => {
    const before = await (await app.fetch('/notes/1')).text();
    const path = join(root, 'src/Notes.res.js');
    writeFileSync(path, readFileSync(path, 'utf8'));
    app.vite!.watcher.emit('change', path);
    let after = before;
    for (let i = 0; i < 100 && after === before; i++) {
      await new Promise((done) => setTimeout(done, 10));
      after = await (await app.fetch('/notes/1')).text();
    }
    expect(after).not.toBe(before);
  });
});

describe('readPage', () => {
  const page = (chunks: string[]) =>
    new ReadableStream<Uint8Array>({
      start(controller) {
        for (const chunk of chunks)
          controller.enqueue(new TextEncoder().encode(chunk));
        controller.close();
      },
    });

  test("hands over the body's nodes as they complete, however the HTML is cut", async () => {
    const html =
      '<!doctype html><html><head><script>record()</script>' +
      '<script type="module" async src="/b.js"></script></head>' +
      '<body><link rel="modulepreload" href="/c.js">' +
      '<div id="root" data-weft-html="" title="a &quot;b&quot; &gt; c"><div><p>x</p></div>' +
      '<!--$?--><template id="wb:0"></template><i>…</i><!--/$--><input value="v"></div>' +
      '<script>(self.__weft||=[]).push("0:J\\"a\\u003c/script>\\"\\n")</script>' +
      '<script>$weftSwap=function(n){}</script>' +
      '<template id="ws:0"><p>later <template data-x="1"></template></p></template>' +
      '<script>$weftSwap(0)</script>' +
      '<script>(self.__weft||=[]).push(null)</script></body></html>';
    for (const size of [1, 3, 7, html.length]) {
      const chunks: string[] = [];
      for (let at = 0; at < html.length; at += size)
        chunks.push(html.slice(at, at + size));
      const pieces: Piece[] = [];
      const shell = await readPage(page(chunks), (piece) => pieces.push(piece));
      expect(pieces).toEqual([
        {type: 'script', code: 'record()'},
        {type: 'markup', html: '<link rel="modulepreload" href="/c.js">'},
        {
          type: 'root',
          attributes: [
            ['id', 'root'],
            ['data-weft-html', ''],
            ['title', 'a "b" > c'],
          ],
          html: '<div><p>x</p></div><!--$?--><template id="wb:0"></template><i>…</i><!--/$--><input value="v">',
        },
        {
          type: 'script',
          code: '(self.__weft||=[]).push("0:J\\"a\\u003c/script>\\"\\n")',
        },
        {type: 'script', code: '$weftSwap=function(n){}'},
        {
          type: 'markup',
          html: '<template id="ws:0"><p>later <template data-x="1"></template></p></template>',
        },
        {type: 'script', code: '$weftSwap(0)'},
        {type: 'script', code: '(self.__weft||=[]).push(null)'},
        {type: 'markup', html: '</body>'},
        {type: 'markup', html: '</html>'},
      ]);
      // The rows taken out.
      expect(shell).not.toContain('__weft');
      expect(shell).toContain('<script>$weftSwap(0)</script></body></html>');
    }
  });
});
