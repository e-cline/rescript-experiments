import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {isolated} from './fixtures.ts';
import {fill} from './readme.ts';

const recording = isolated([
  {name: 'A.get n=10', group: 'get n=10', times: [10, 10, 10, 10, 10]},
  {name: 'B.get n=10', group: 'get n=10', times: [20, 20, 20, 20, 20]},
  {name: 'A.get n=100', group: 'get n=100', times: [100, 100, 100, 100, 100]},
  {name: 'B.get n=100', group: 'get n=100', times: [150, 150, 150, 150, 150]},
  {name: 'pipe | name', times: [5, 5, 5, 5, 7]},
]);

const block = (attributes: string, inside = '') =>
  `<!-- res-bench ${attributes} -->\n${inside}<!-- /res-bench -->`;

describe('fill', () => {
  it('replaces what a block holds with a table and leaves the rest alone', () => {
    const markdown = `# Title\n\nBefore.\n\n${block('filter="\\.get "', 'stale\n')}\n\nAfter.\n`;
    const {markdown: filled, blocks} = fill(markdown, recording, 'README.md');
    assert.equal(blocks, 1);
    assert.ok(filled.startsWith('# Title\n\nBefore.\n\n<!-- res-bench'));
    assert.ok(filled.endsWith('<!-- /res-bench -->\n\nAfter.\n'));
    assert.ok(!filled.includes('stale'));
    const lines = filled.split('\n');
    assert.ok(lines.some((line) => /^\| +\| +A \| +B \|$/.test(line)));
    assert.ok(
      lines.some((line) =>
        /^\| get n=10 +\| +10\.00 ns \(1\.00x\) \| +20\.00 ns \(2\.00x\) \|$/.test(
          line,
        ),
      ),
    );
  });

  it('gives the same file when filled again', () => {
    const once = fill(block('filter="."'), recording, 'README.md').markdown;
    assert.equal(fill(once, recording, 'README.md').markdown, once);
  });

  it('fills every block, each with its own selection', () => {
    const markdown = `${block('filter="^A\\."')}\n\n${block('filter="pipe"')}\n`;
    const {markdown: filled, blocks} = fill(markdown, recording, 'README.md');
    assert.equal(blocks, 2);
    const [first, second] = filled.split('<!-- res-bench filter="pipe" -->');
    assert.ok(
      first!.includes('A.get') === false && first!.includes('| get n=10'),
    );
    assert.ok(!first!.includes('pipe'));
    assert.ok(second!.includes('pipe \\| name'));
  });

  it('expresses times as multiples of the implementation `relative` names', () => {
    const filled = fill(
      block('filter="\\.get " relative="B"'),
      recording,
      'README.md',
    ).markdown;
    assert.ok(
      filled.includes('(0.50x)') &&
        filled.includes("each time's multiple of B's"),
    );
  });

  it("wraps the line under a table at the formatter's 100 columns", () => {
    const filled = fill(
      block('filter="pipe"'),
      recording,
      'README.md',
    ).markdown;
    // Everything that isn't the table, a comment or a blank line.
    const prose = filled
      .split('\n')
      .filter(
        (line) =>
          line !== '' && !line.startsWith('|') && !line.startsWith('<!--'),
      );
    assert.ok(prose.length > 1);
    for (const line of prose) {
      assert.ok(line.length <= 100, line);
    }
  });

  it('marks a noisy benchmark, and says what the mark means', () => {
    const filled = fill(
      block('filter="pipe"'),
      recording,
      'README.md',
    ).markdown;
    assert.ok(filled.includes('5.00 ns\\*'));
    assert.ok(filled.includes('\\* marks a benchmark'));
  });

  it('says where the measurements came from', () => {
    const filled = fill(
      block('filter="pipe"'),
      recording,
      'README.md',
    ).markdown;
    assert.ok(filled.replaceAll('\n', ' ').includes('Measured at 0123456'));
  });

  describe('refuses, naming the line,', () => {
    const refuses = (markdown: string, message: RegExp) =>
      assert.throws(() => fill(markdown, recording, 'README.md'), message);

    it('a block nothing closes', () =>
      refuses(
        `one\n<!-- res-bench filter="." -->\n`,
        /README\.md:2: no <!-- \/res-bench -->/,
      ));
    it('a block without a filter', () =>
      refuses(block('relative="A"'), /README\.md:1: needs a filter/));
    it('an attribute it does not know', () =>
      refuses(block('filter="." colour="red"'), /unknown attribute colour/));
    it('a filter nothing matches', () =>
      refuses(
        `a\nb\n${block('filter="nothing"')}`,
        /README\.md:3: No benchmark/,
      ));
    it('a relative implementation the filter does not select', () =>
      refuses(block('filter="^A\\." relative="B"'), /relative="B" names none/));
  });

  it('finds no blocks in a file without any', () => {
    assert.deepEqual(fill('# Nothing here\n', recording, 'README.md'), {
      markdown: '# Nothing here\n',
      blocks: 0,
    });
  });
});
