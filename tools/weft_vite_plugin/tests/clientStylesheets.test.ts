// @vitest-environment jsdom
import {describe, expect, test} from 'vite-plus/test';

import {replaceStylesheet} from '../src/internal/replaceStylesheet.js';
import {clientCode} from '../src/internal/virtualModules.js';

const links = () =>
  [...document.querySelectorAll('link[rel="stylesheet"]')].map((link) =>
    link.getAttribute('href'),
  );

describe("virtual:weft/client's stylesheet swap", () => {
  test('is in the client module, run on `weft:css`', () => {
    expect(clientCode()).toContain(`export ${replaceStylesheet.toString()}`);
    expect(clientCode()).toContain(
      '"weft:css", ({href}) => replaceStylesheet(href)',
    );
  });

  test('puts a fresh link after the old, and takes the old away once the new has loaded', async () => {
    document.head.innerHTML =
      '<link rel="stylesheet" href="/node_modules/.weft-css/wabc123.css">' +
      '<link rel="stylesheet" href="/other.css">';
    replaceStylesheet('/node_modules/.weft-css/wabc123.css');
    const [old, fresh] = links();
    expect(old).toBe('/node_modules/.weft-css/wabc123.css');
    expect(fresh).toMatch(/^\/node_modules\/\.weft-css\/wabc123\.css\?t=\d+$/);
    expect(links()).toHaveLength(3);
    document
      .querySelectorAll('link[rel="stylesheet"]')[1]!
      .dispatchEvent(new Event('load'));
    expect(links()).toEqual([fresh, '/other.css']);
    // And again: the link it swapped in has a query, and is swapped in turn.
    replaceStylesheet('/node_modules/.weft-css/wabc123.css');
    expect(links()).toHaveLength(3);
  });
});
