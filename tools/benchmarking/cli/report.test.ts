import assert from 'node:assert/strict';
import {describe, it} from 'node:test';

import {isolated} from './fixtures.ts';
import {
  change,
  comparison,
  environmentDifferences,
  formatTime,
  spreadOf,
  summary,
  uCounts,
} from './report.ts';

/**
 * The Mann-Whitney U distribution by brute force: every way of choosing which
 * `n` of `n + m` ranks are the first sample's, and how many pairs the second
 * sample wins in each.
 */
const bruteForceUCounts = (n: number, m: number): number[] => {
  const counts = Array.from({length: n * m + 1}, () => 0);
  const choose = (start: number, chosen: number[]) => {
    if (chosen.length === n) {
      // U is the sum of the first sample's ranks, less the least it could be.
      const u = chosen.reduce((sum, rank) => sum + rank, 0) - (n * (n - 1)) / 2;
      counts[u]! += 1;
      return;
    }
    for (let rank = start; rank < n + m; rank++) {
      choose(rank + 1, [...chosen, rank]);
    }
  };
  choose(0, []);
  return counts;
};

describe('uCounts', () => {
  for (const [n, m] of [
    [1, 1],
    [2, 3],
    [3, 3],
    [4, 6],
    [5, 5],
    [6, 4],
  ] as const) {
    it(`matches brute force for ${n} and ${m}`, () => {
      assert.deepEqual(uCounts(n, m), bruteForceUCounts(n, m));
    });
  }

  it('counts every arrangement once', () => {
    // 10 choose 5.
    assert.equal(
      uCounts(5, 5).reduce((sum, count) => sum + count, 0),
      252,
    );
  });
});

describe('change', () => {
  const base = [10, 11, 12, 13, 14];

  it('finds no change between identical samples', () => {
    const {estimate, low, high} = change([5, 5, 5, 5, 5], [5, 5, 5, 5, 5]);
    assert.equal(estimate, 1);
    assert.ok(low <= 1 && high >= 1);
  });

  it('estimates the typical ratio between the two sides', () => {
    assert.equal(change([1, 1, 1, 1, 1], [2, 2, 2, 2, 2]).estimate, 2);
  });

  it('calls a change when every head process beat every base process', () => {
    const {low, high} = change(base, [5, 6, 7, 8, 9]);
    // With 5 a side, the 99% interval runs from the smallest ratio to the
    // largest.
    assert.equal(low, 5 / 14);
    assert.equal(high, 9 / 10);
    assert.ok(high < 1);
  });

  it("doesn't call a change when one pair of processes overlaps", () => {
    // P(U <= 1) is 2/252, more than the 0.5% a 99% interval leaves each side.
    const {high} = change(base, [5, 6, 7, 8, 10.5]);
    assert.ok(high > 1);
  });

  it('gives an unbounded interval with too few processes to tell', () => {
    const {low, high} = change([10, 11, 12, 13], [1, 2, 3, 4]);
    assert.equal(low, 0);
    assert.equal(high, Infinity);
  });
});

describe('spreadOf', () => {
  it('measures the gap between the extremes against the median', () => {
    const spread = spreadOf([90, 100, 105]);
    assert.equal(spread.median, 100);
    assert.equal(spread.spread, 0.15);
    assert.equal(spread.noisy, true);
  });

  it('uses the middle two values of an even count', () => {
    assert.equal(spreadOf([1, 2, 3, 10]).median, 2.5);
  });
});

describe('formatTime', () => {
  it('picks a unit for the size', () => {
    assert.equal(formatTime(512), '512.00 ns');
    assert.equal(formatTime(1_500), '1.50 µs');
    assert.equal(formatTime(2_500_000), '2.50 ms');
    assert.equal(formatTime(3e9), '3.00 s');
  });
});

describe('summary', () => {
  const recording = isolated([
    {name: 'A.get n=10', group: 'get n=10', times: [10, 10, 10]},
    {name: 'Belt.Map.get n=10', group: 'get n=10', times: [20, 20, 20]},
    {name: 'A.get n=100', group: 'get n=100', times: [100, 130, 100]},
    {name: 'something else', times: [5, 5, 5]},
  ]);
  const text = summary(recording);

  it('pivots benchmarks with an implementation, a column each', () => {
    const header = text.split('\n').find((line) => line.includes('Belt.Map'));
    assert.ok(header?.includes('A'));
    const row = text.split('\n').find((line) => line.startsWith('get n=10 '));
    assert.ok(
      row?.includes('1.00x') && row.includes('2.00x'),
      row ?? 'no such row',
    );
  });

  it('marks a noisy benchmark in the pivot', () => {
    const row = text.split('\n').find((line) => line.startsWith('get n=100'));
    assert.ok(row?.includes('*'), row ?? 'no such row');
  });

  it('lists the rest with their spread', () => {
    const row = text.split('\n').find((line) => line.startsWith('something'));
    assert.ok(row?.includes('0.0%'), row ?? 'no such row');
  });
});

describe('comparison', () => {
  it('counts what changed', () => {
    const base = isolated([
      {name: 'fast', times: [10, 11, 12, 13, 14]},
      {name: 'same', times: [10, 10, 10, 10, 10]},
      {name: 'only in base', times: [1, 1, 1, 1, 1]},
    ]);
    const head = isolated([
      {name: 'fast', times: [5, 6, 7, 8, 9]},
      {name: 'same', times: [10, 10, 10, 10, 10]},
    ]);
    const text = comparison(base, head);
    assert.ok(text.includes('1 faster, 0 slower, 1 with no change'), text);
    assert.ok(text.includes('Only in base: only in base'), text);
  });
});

describe('environmentDifferences', () => {
  const recording = (budgetMs?: number) =>
    isolated(
      [{name: 'a', times: [1]}],
      budgetMs === undefined ? {} : {budgetMs},
    );

  it('finds nothing to say about recordings made the same way', () => {
    assert.deepEqual(
      environmentDifferences(recording(200), recording(200)),
      [],
    );
  });

  it('notes a different sampling budget', () => {
    assert.deepEqual(environmentDifferences(recording(200), recording(50)), [
      'The sampling budget differs: 200 ms (base), 50 ms (head).',
    ]);
  });

  it("takes a recording without a budget to have mitata's own", () => {
    assert.deepEqual(environmentDifferences(recording(), recording(706)), []);
  });
});
