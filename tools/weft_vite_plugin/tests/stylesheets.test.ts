// @vitest-environment jsdom
import {describe, expect, test} from 'vite-plus/test';

import {loadStylesheets} from '../src/testing.js';

describe("the harness's stylesheets", () => {
  test('each link added to the head loads, a task later, and is recorded', async () => {
    const loaded: string[] = [];
    loadStylesheets(document, (href) => loaded.push(href));
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = '/a.css';
    const fired = new Promise<string>((resolve) =>
      link.addEventListener('load', () => resolve('load')),
    );
    document.head.append(link);
    // A script is no stylesheet.
    document.head.append(document.createElement('script'));
    expect(await fired).toBe('load');
    expect(loaded).toEqual(['/a.css']);
  });

  test('is told to the page opened latest', async () => {
    const first: string[] = [];
    const second: string[] = [];
    loadStylesheets(document, (href) => first.push(href));
    loadStylesheets(document, (href) => second.push(href));
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = '/b.css';
    const fired = new Promise((resolve) =>
      link.addEventListener('load', resolve),
    );
    document.head.append(link);
    await fired;
    expect([first, second]).toEqual([[], ['/b.css']]);
  });
});
