/**
 * The tables `res-bench` prints: a summary of one recording, and a comparison of
 * two.
 *
 * Both work from each benchmark's per-call average in each process. Within one
 * process mitata's measurements are tight; what varies is the process itself
 * (one can come out tens of percent slower than the next, running the same
 * bundle), so the process is the unit everything here counts and compares.
 */
import type {Recording} from './results.ts';
import {averagesByName, identities} from './results.ts';

export const formatTime = (nanoseconds: number): string =>
  nanoseconds < 1e3
    ? `${nanoseconds.toFixed(2)} ns`
    : nanoseconds < 1e6
      ? `${(nanoseconds / 1e3).toFixed(2)} µs`
      : nanoseconds < 1e9
        ? `${(nanoseconds / 1e6).toFixed(2)} ms`
        : `${(nanoseconds / 1e9).toFixed(2)} s`;

const formatPercent = (fraction: number): string =>
  `${fraction >= 0 ? '+' : '-'}${Math.abs(fraction * 100).toFixed(1)}%`;

const median = (values: readonly number[]): number => {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = sorted.length >> 1;
  return sorted.length % 2 === 1
    ? sorted[middle]!
    : (sorted[middle - 1]! + sorted[middle]!) / 2;
};

/**
 * Lays out `rows` in columns: the first left-aligned, the rest right-aligned so
 * that times and percentages line up on their units.
 */
const table = (rows: string[][]): string => {
  const widths = rows[0]!.map((_, column) =>
    Math.max(...rows.map((row) => row[column]?.length ?? 0)),
  );
  return rows
    .map((row) =>
      row
        .map((cell, column) =>
          column === 0
            ? cell.padEnd(widths[column]!)
            : cell.padStart(widths[column]!),
        )
        .join('  ')
        .trimEnd(),
    )
    .join('\n');
};

/**
 * How far apart a benchmark's processes landed, as a fraction of their median,
 * above which it's marked noisy.
 */
export const noisySpread = 0.1;

/** A benchmark's processes summarized: their median, extremes, and spread. */
export type Spread = {
  median: number;
  fastest: number;
  slowest: number;
  /** The gap between the fastest and slowest, as a fraction of the median. */
  spread: number;
  noisy: boolean;
};

export const spreadOf = (averages: readonly number[]): Spread => {
  const middle = median(averages);
  const fastest = Math.min(...averages);
  const slowest = Math.max(...averages);
  const spread = (slowest - fastest) / middle;
  return {
    median: middle,
    fastest,
    slowest,
    spread,
    noisy: spread > noisySpread,
  };
};

/**
 * The benchmarks `Comparison` registered, one row per operation and size, with
 * a column per implementation: each one's median, marked `*` if it's noisy, and
 * how many times the row's fastest median that is. `None` if there are none.
 */
const pivot = (recording: Recording): string | null => {
  const averages = averagesByName(recording);
  const compared = [...identities(recording).values()].filter(
    (identity) =>
      identity.implementation !== undefined && averages.has(identity.name),
  );
  if (compared.length === 0) {
    return null;
  }
  const implementations = [
    ...new Set(compared.map((identity) => identity.implementation!)),
  ];
  // Each operation's groups together, in the order operations first appear:
  // programs register every operation at one size, then the next.
  const operations = [
    ...new Set(compared.map((identity) => identity.operation)),
  ];
  const groups = [...new Set(compared.map((identity) => identity.group!))].sort(
    (a, b) =>
      operations.indexOf(
        compared.find((identity) => identity.group === a)!.operation,
      ) -
      operations.indexOf(
        compared.find((identity) => identity.group === b)!.operation,
      ),
  );
  const rows = [['', ...implementations]];
  let previousOperation: string | undefined;
  for (const group of groups) {
    const inGroup = compared.filter((identity) => identity.group === group);
    const operation = inGroup[0]!.operation;
    if (previousOperation !== undefined && operation !== previousOperation) {
      rows.push([]);
    }
    previousOperation = operation;
    const spreads = new Map(
      inGroup.map((identity) => [
        identity.implementation!,
        spreadOf(averages.get(identity.name)!),
      ]),
    );
    const fastest = Math.min(
      ...[...spreads.values()].map(({median}) => median),
    );
    rows.push([
      group,
      ...implementations.map((implementation) => {
        const spread = spreads.get(implementation);
        return spread === undefined
          ? ''
          : `${formatTime(spread.median)}${spread.noisy ? '*' : ' '} ${(spread.median / fastest).toFixed(2).padStart(6)}x`;
      }),
    ]);
  }
  return table(rows);
};

/**
 * Each benchmark's median over the recording's processes. Those `Comparison`
 * registered are pivoted, an implementation to a column (see `pivot`); the rest
 * are listed with their fastest and slowest process and the gap between them.
 */
export const summary = (recording: Recording): string => {
  const averages = averagesByName(recording);
  const benchmarkIdentities = identities(recording);
  const pivoted = pivot(recording);
  const rows = [['', 'median', 'fastest', 'slowest', 'spread']];
  for (const [name, values] of averages) {
    if (
      pivoted !== null &&
      benchmarkIdentities.get(name)?.implementation !== undefined
    ) {
      continue;
    }
    const {median, fastest, slowest, spread, noisy} = spreadOf(values);
    rows.push([
      name,
      formatTime(median),
      formatTime(fastest),
      formatTime(slowest),
      `${(spread * 100).toFixed(1)}%${noisy ? ' noisy' : ''}`,
    ]);
  }
  const noisy = [...averages.values()].filter(
    (values) => spreadOf(values).noisy,
  ).length;
  return [
    `${describe(recording)}: average time per call, ${howRun(recording)}`,
    ...(pivoted === null
      ? []
      : [
          '',
          pivoted,
          '',
          "Each time is the median of its benchmark's processes, then how many times the row's fastest median it is.",
        ]),
    ...(rows.length > 1 ? ['', table(rows)] : []),
    ...(noisy > 0
      ? [
          '',
          `${noisy} ${pivoted === null ? 'marked noisy' : 'marked noisy or *'}: their processes landed more than ${noisySpread * 100}% apart, so a single run of any of them can be off by that much.`,
        ]
      : []),
  ].join('\n');
};

/**
 * How sure a comparison has to be before it calls a change: a 99% interval.
 * A comparison tests every benchmark at once, and at 95% one benchmark in
 * twenty with no real change would be flagged anyway, two or three in a full
 * B-tree comparison.
 */
export const confidence = 0.99;

/**
 * How many of the ways of interleaving `n` values with `m` others give each
 * Mann-Whitney U from 0 to `n * m`, if neither side tends to be larger. These
 * are the coefficients of the Gaussian binomial coefficient (n + m choose n):
 * the product over i from 1 to n of (1 - q^(m + i)) / (1 - q^i).
 */
export const uCounts = (n: number, m: number): number[] => {
  const counts = Array.from({length: n * m + 1}, (_, u) => (u === 0 ? 1 : 0));
  for (let i = 1; i <= n; i++) {
    for (let u = counts.length - 1; u >= m + i; u--) {
      counts[u]! -= counts[u - (m + i)]!;
    }
    for (let u = i; u < counts.length; u++) {
      counts[u]! += counts[u - i]!;
    }
  }
  return counts;
};

/**
 * The change in time per call from `base` to `head`, as a ratio, with an
 * interval for it at `confidence`. The estimate is the Hodges-Lehmann one, the
 * median of the ratios between every process on one side and every process on
 * the other; the interval is the exact one that goes with the Mann-Whitney
 * test. Neither assumes anything about how the processes' times are spread,
 * which matters for benchmarks that land in one of two places.
 *
 * With too few processes for any interval to reach `confidence`, the interval
 * is unbounded: 5 a side is the least that can tell anything apart at 99%.
 */
export const change = (
  base: readonly number[],
  head: readonly number[],
): {estimate: number; low: number; high: number} => {
  const ratios = head
    .flatMap((h) => base.map((b) => h / b))
    .sort((a, b) => a - b);
  // The interval runs from the k-th smallest ratio to the k-th largest, for
  // the largest k leaving less than (1 - confidence) / 2 of the U
  // distribution below it.
  const counts = uCounts(base.length, head.length);
  const total = counts.reduce((sum, count) => sum + count, 0);
  let k = 0;
  let below = 0;
  while ((below + counts[k]!) / total <= (1 - confidence) / 2) {
    below += counts[k]!;
    k += 1;
  }
  return {
    estimate: median(ratios),
    low: k === 0 ? 0 : ratios[k - 1]!,
    high: k === 0 ? Infinity : ratios[ratios.length - k]!,
  };
};

/** How `recording`'s benchmarks were run: how many processes, of what kind. */
const howRun = (recording: Recording): string => {
  const count = Math.max(
    ...[...averagesByName(recording).values()].map(({length}) => length),
  );
  const processes = `${count} ${count === 1 ? 'process' : 'processes'}`;
  return recording.isolated
    ? `each benchmark in ${processes} of its own`
    : `${processes}, each running every benchmark`;
};

const describe = (recording: Recording): string => {
  const {source} = recording;
  const commit = source.commit.slice(0, 7) + (source.dirty ? '+changes' : '');
  return `${recording.package} (${recording.entry}) at ${source.label === commit ? commit : `${source.label} (${commit})`}`;
};

/**
 * How `head` compares with `base`, benchmark by benchmark: each side's median
 * time per call, and the change between them with an interval for it (see
 * `change`). A change counts only when its interval leaves out zero;
 * otherwise the processes on the two sides overlap too much to tell a
 * difference from noise.
 */
export const comparison = (base: Recording, head: Recording): string => {
  const baseAverages = averagesByName(base);
  const headAverages = averagesByName(head);
  const rows = [
    ['', 'base', 'head', 'change', `${confidence * 100}% interval`, ''],
  ];
  let unbounded = false;
  const counts = {faster: 0, slower: 0, unchanged: 0};
  for (const [name, baseValues] of baseAverages) {
    const headValues = headAverages.get(name);
    if (headValues === undefined) {
      continue;
    }
    const {estimate, low, high} = change(baseValues, headValues);
    unbounded ||= high === Infinity;
    const verdict = high < 1 ? 'faster' : low > 1 ? 'slower' : 'unchanged';
    counts[verdict] += 1;
    rows.push([
      name,
      formatTime(median(baseValues)),
      formatTime(median(headValues)),
      formatPercent(estimate - 1),
      high === Infinity
        ? 'unbounded'
        : `[${formatPercent(low - 1)}, ${formatPercent(high - 1)}]`,
      verdict === 'unchanged' ? '' : verdict,
    ]);
  }
  const onlyIn = (from: Map<string, number[]>, other: Map<string, number[]>) =>
    [...from.keys()].filter((name) => !other.has(name));
  const onlyBase = onlyIn(baseAverages, headAverages);
  const onlyHead = onlyIn(headAverages, baseAverages);
  return [
    `base: ${describe(base)}, ${howRun(base)}`,
    `head: ${describe(head)}, ${howRun(head)}`,
    '',
    table(rows),
    '',
    `${counts.faster} faster, ${counts.slower} slower, ${counts.unchanged} with no change the processes can tell apart from noise.`,
    'Changes are in time per call: negative is faster.',
    ...(unbounded
      ? [
          `Some intervals are unbounded: telling anything apart at ${confidence * 100}% takes at least 5 processes a side.`,
        ]
      : []),
    ...(onlyBase.length > 0 ? [`Only in base: ${onlyBase.join(', ')}`] : []),
    ...(onlyHead.length > 0 ? [`Only in head: ${onlyHead.join(', ')}`] : []),
  ].join('\n');
};

/**
 * How long a recording's processes sampled each benchmark for, in
 * milliseconds: 706 for recordings from before `res-bench` set it (see
 * `Recording`'s `budgetMs`).
 */
const budgetOf = (recording: Recording): number => recording.budgetMs ?? 706;

/**
 * Differences between two recordings' environments, or how they were
 * measured, that make comparing them questionable, as sentences.
 */
export const environmentDifferences = (
  base: Recording,
  head: Recording,
): string[] => {
  const keys = ['node', 'cpu', 'platform', 'arch', 'mitata'] as const;
  return [
    ...keys.flatMap((key) =>
      base.environment[key] === head.environment[key]
        ? []
        : [
            `${key} differs: ${base.environment[key]} (base), ${head.environment[key]} (head).`,
          ],
    ),
    ...(budgetOf(base) === budgetOf(head)
      ? []
      : [
          `The sampling budget differs: ${budgetOf(base)} ms (base), ${budgetOf(head)} ms (head).`,
        ]),
  ];
};
