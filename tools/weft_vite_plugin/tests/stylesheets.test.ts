// @vitest-environment jsdom
import {describe, expect, test} from 'vite-plus/test';

import {loadStylesheets, Page, readPage, type Piece} from '../src/testing.js';

const html = (text: string) =>
  new Response(text, {headers: {'content-type': 'text/html'}});

const tick = () => new Promise((resolve) => setTimeout(resolve, 0));

/** A harness page over `body` (no app, no bootstrap): what the harness does with its HTML. */
function pageOf(text: string): Page {
  const container = document.createElement('div');
  document.body.append(container);
  const page = new Page(
    {} as never,
    container,
    (f) => f(),
    async () => undefined,
    Promise.resolve(html(text)),
    '/',
    0,
    false,
  );
  loadStylesheets(document, (link) => page.addedStylesheet(link));
  return page;
}

describe("the harness's stylesheets", () => {
  test("reads the head's stylesheets, unescaped, as pieces of their own", async () => {
    const pieces: Piece[] = [];
    await readPage(
      html(
        '<!doctype html><html><head><link rel="stylesheet" href="/a.css?x=1&amp;y=2">' +
          '<script>1</script></head><body><div id="root"></div></body></html>',
      ).body!,
      (piece) => pieces.push(piece),
    );
    expect(pieces.slice(0, 2)).toEqual([
      {type: 'stylesheet', href: '/a.css?x=1&y=2'},
      {type: 'script', code: '1'},
    ]);
  });

  test("applies the head's as loaded; loads the others a task later, or once released", async () => {
    document.head.innerHTML = '';
    const page = pageOf(
      '<!doctype html><html><head><link rel="stylesheet" href="/assets/waaaaaa-1x.css">' +
        '</head><body><div id="root" data-weft-html=""><p class="A-x_waaaaaa">x</p></div></body></html>',
    );
    await page.shell;
    // The shell's sheet was in the head: the shell is styled.
    expect(page.unstyled()).toEqual([]);
    // Content that needs another sheet, before it has loaded.
    page.container.insertAdjacentHTML(
      'beforeend',
      '<i class="B-y_wbbbbbb other">y</i>',
    );
    expect(page.unstyled()).toEqual(['<i class="B-y_wbbbbbb other">']);
    page.holdStylesheets('wbbbbbb');
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.setAttribute('href', '/assets/wbbbbbb-2y.css');
    const loaded = new Promise((resolve) =>
      link.addEventListener('load', resolve),
    );
    document.head.append(link);
    await tick();
    await tick();
    expect(page.unstyled()).toHaveLength(1);
    page.releaseStylesheets();
    await loaded;
    expect(page.unstyled()).toEqual([]);
    expect(page.stylesheets).toEqual(['/assets/wbbbbbb-2y.css']);
  });
});
