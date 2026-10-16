import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {isolated} from './fixtures.ts';
import {comparisonPage, recordingPage} from './html.ts';

const sized = [
  {name: 'A.get n=10', group: 'get n=10', times: [10, 11, 12]},
  {name: 'A.get n=100', group: 'get n=100', times: [20, 21, 22]},
  {name: 'B.get n=10', group: 'get n=10', times: [15, 15, 15]},
  {name: 'B.get n=100', group: 'get n=100', times: [30, 30, 30]},
];
const hostile = {
  name: '<img src=x onerror=alert(1)> & "quotes"',
  times: [5, 5, 5],
};

describe('recordingPage', () => {
  const page = recordingPage(isolated([...sized, hostile]));

  it('is a complete page', () => {
    assert.ok(page.startsWith('<!doctype html>'));
    assert.ok(page.trimEnd().endsWith('</html>'));
  });

  it('charts an operation measured at more than one size', () => {
    assert.ok(page.includes('How time grows with size'));
    assert.ok(page.includes('<figcaption>get</figcaption>'));
    // A line for each implementation.
    assert.equal(page.match(/class="line"/g)?.length, 2);
  });

  it("doesn't chart what was measured at only one size", () => {
    const single = recordingPage(
      isolated([{name: 'A.get n=10', group: 'get n=10', times: [1, 1, 1]}]),
    );
    assert.ok(!single.includes('How time grows with size'));
  });

  it('never lets a benchmark name become markup', () => {
    assert.ok(!page.includes('<img'));
    assert.ok(
      page.includes(
        '&lt;img src=x onerror=alert(1)&gt; &amp; &quot;quotes&quot;',
      ),
    );
  });

  it('builds tooltips with textContent, not markup', () => {
    assert.ok(!page.includes('innerHTML'));
    assert.ok(page.includes('textContent'));
  });
});

describe('comparisonPage', () => {
  const base = isolated([
    {name: 'fast', times: [10, 11, 12, 13, 14]},
    {name: 'same', times: [10, 10, 10, 10, 10]},
    {name: 'only in base', times: [1, 1, 1, 1, 1]},
  ]);
  const head = isolated([
    {name: 'fast', times: [5, 6, 7, 8, 9]},
    {name: 'same', times: [10, 10, 10, 10, 10]},
  ]);
  const page = comparisonPage(base, head);

  it('labels a change, not only colors it', () => {
    assert.equal(page.match(/▼ faster/g)?.length, 1);
    assert.ok(!page.includes('▲ slower'));
  });

  it('shows only the benchmarks both sides measured', () => {
    assert.ok(!page.includes('only in base'));
    assert.ok(page.includes('>same</th>'));
  });
});
