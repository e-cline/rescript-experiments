import type {Spread} from './report.ts';
import {
  change,
  confidence,
  formatTime,
  noisySpread,
  spreadOf,
} from './report.ts';
/**
 * `res-bench report`: a recording, or a comparison of two, as one
 * self-contained HTML page with charts, for exploring what the terminal tables
 * only list.
 *
 * - How each operation's time grows with the size it was measured at, one
 *   small chart per operation and a line per implementation, for benchmarks
 *   `Comparison` registered (see `identities` in `results.ts`).
 * - Every benchmark in a table, each with a strip of its processes' times
 *   around their median, which is where a benchmark that lands in one of two
 *   places shows itself.
 * - For a comparison, each benchmark's change with its interval, drawn.
 *
 * Everything is drawn here, as SVG, with no library; the page's one script
 * shows tooltips.
 */
import type {Identity, Recording} from './results.ts';
import {averagesByName, identities} from './results.ts';

const escape = (text: string): string =>
  text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/** What a tooltip shows: a title, then rows of value and label. */
type Tip = {
  title: string;
  rows: {value: string; label: string; series?: number}[];
};

/** The attributes that give an element `tip` on hover and focus. */
const tipAttributes = (tip: Tip): string =>
  `tabindex="0" data-tip="${escape(JSON.stringify(tip))}"`;

const formatSize = (size: number): string => size.toLocaleString('en-US');

const formatPercent = (fraction: number): string =>
  `${fraction >= 0 ? '+' : '-'}${Math.abs(fraction * 100).toFixed(1)}%`;

/**
 * Round values for a log axis covering `low` to `high`: 1, 2 and 5 times
 * powers of ten, or only the powers of ten if those would crowd it.
 */
const logTicks = (low: number, high: number): number[] => {
  const ticks: number[] = [];
  for (
    let power = Math.floor(Math.log10(low));
    power <= Math.ceil(Math.log10(high));
    power++
  ) {
    for (const step of [1, 2, 5]) {
      const tick = step * 10 ** power;
      if (tick >= low && tick <= high) {
        ticks.push(tick);
      }
    }
  }
  return ticks.length > 6
    ? ticks.filter((tick) => Number.isInteger(Math.log10(tick)))
    : ticks;
};

/** The nearest 1, 2 or 5 times a power of ten at or below `value`. */
const niceFloor = (value: number): number => {
  const power = 10 ** Math.floor(Math.log10(value));
  return [5, 2, 1].map((step) => step * power).find((tick) => tick <= value)!;
};

/** The nearest 1, 2 or 5 times a power of ten at or above `value`. */
const niceCeiling = (value: number): number => {
  const power = 10 ** Math.floor(Math.log10(value));
  return [1, 2, 5, 10]
    .map((step) => step * power)
    .find((tick) => tick >= value)!;
};

const logScale =
  (low: number, high: number, from: number, to: number) =>
  (value: number): number =>
    low === high
      ? (from + to) / 2
      : from +
        ((Math.log(value) - Math.log(low)) / (Math.log(high) - Math.log(low))) *
          (to - from);

/** A benchmark `Comparison` registered, with the times its processes took. */
type Measured = Identity & {averages: number[]; spread: Spread};

const measured = (recording: Recording): Measured[] => {
  const averages = averagesByName(recording);
  return [...identities(recording).values()].flatMap((identity) => {
    const values = averages.get(identity.name);
    return values === undefined
      ? []
      : [{...identity, averages: values, spread: spreadOf(values)}];
  });
};

/** The implementations among `benchmarks`, in the order they first appear. */
const implementationsOf = (benchmarks: Measured[]): string[] => [
  ...new Set(benchmarks.flatMap(({implementation}) => implementation ?? [])),
];

/** A short line in an implementation's color, keying a legend or tooltip row. */
const lineKey = (series: number): string =>
  `<svg class="key" width="16" height="10" aria-hidden="true"><line x1="1" y1="5" x2="15" y2="5" stroke="var(--series-${series})" stroke-width="2" stroke-linecap="round"/></svg>`;

const legend = (implementations: string[]): string =>
  `<ul class="legend">${implementations
    .map(
      (implementation, index) =>
        `<li>${lineKey(index + 1)}${escape(implementation)}</li>`,
    )
    .join('')}</ul>`;

/**
 * One operation's chart: median time per call against size, on log scales, a
 * line per implementation, and every process as a faint dot. Hovering a size
 * lists every implementation's median and range there.
 */
const scalingChart = (
  operation: string,
  benchmarks: Measured[],
  implementations: string[],
): string => {
  const width = 320;
  const height = 200;
  const margin = {top: 10, right: 16, bottom: 30, left: 64};
  const sizes = [...new Set(benchmarks.map(({size}) => size!))].sort(
    (a, b) => a - b,
  );
  const all = benchmarks.flatMap(({averages}) => averages);
  const low = niceFloor(Math.min(...all));
  const high = niceCeiling(Math.max(...all));
  const x = logScale(
    sizes[0]!,
    sizes.at(-1)!,
    margin.left + 12,
    width - margin.right - 12,
  );
  const y = logScale(low, high, height - margin.bottom, margin.top);
  const parameterKey = benchmarks[0]!.parameter!.split('=')[0];

  const grid = logTicks(low, high)
    .map(
      (tick) =>
        `<line class="grid" x1="${margin.left}" x2="${width - margin.right}" y1="${y(tick)}" y2="${y(tick)}"/>` +
        `<text class="tick" x="${margin.left - 6}" y="${y(tick)}" text-anchor="end" dominant-baseline="middle">${escape(formatTime(tick).replace('.00 ', ' '))}</text>`,
    )
    .join('');
  const xAxis =
    `<line class="axis" x1="${margin.left}" x2="${width - margin.right}" y1="${height - margin.bottom}" y2="${height - margin.bottom}"/>` +
    sizes
      .map(
        (size) =>
          `<text class="tick" x="${x(size)}" y="${height - margin.bottom + 16}" text-anchor="middle">${escape(`${parameterKey}=${formatSize(size)}`)}</text>`,
      )
      .join('');

  const series = implementations
    .map((implementation, index) => {
      const points = benchmarks
        .filter((benchmark) => benchmark.implementation === implementation)
        .sort((a, b) => a.size! - b.size!);
      if (points.length === 0) {
        return '';
      }
      const color = `var(--series-${index + 1})`;
      const path = points
        .map(
          ({size, spread}, at) =>
            `${at === 0 ? 'M' : 'L'}${x(size!)},${y(spread.median)}`,
        )
        .join(' ');
      const processes = points
        .flatMap(({size, averages}) =>
          averages.map(
            (average) =>
              `<circle class="process" cx="${x(size!)}" cy="${y(average)}" r="2" fill="${color}"/>`,
          ),
        )
        .join('');
      const markers = points
        .map(
          ({size, spread}) =>
            `<circle class="marker" cx="${x(size!)}" cy="${y(spread.median)}" r="4" fill="${color}"/>`,
        )
        .join('');
      return `<g>${processes}<path class="line" d="${path}" stroke="${color}"/>${markers}</g>`;
    })
    .join('');

  // A band per size, wider than any mark, that snaps the crosshair to it.
  const bands = sizes
    .map((size, at) => {
      const left = at === 0 ? margin.left : (x(sizes[at - 1]!) + x(size)) / 2;
      const right =
        at === sizes.length - 1
          ? width - margin.right
          : (x(size) + x(sizes[at + 1]!)) / 2;
      const tip: Tip = {
        title: `${operation} ${parameterKey}=${formatSize(size)}`,
        rows: implementations.flatMap((implementation, index) => {
          const benchmark = benchmarks.find(
            (candidate) =>
              candidate.implementation === implementation &&
              candidate.size === size,
          );
          return benchmark === undefined
            ? []
            : [
                {
                  value: formatTime(benchmark.spread.median),
                  label: `${implementation} (${formatTime(benchmark.spread.fastest)} to ${formatTime(benchmark.spread.slowest)})`,
                  series: index + 1,
                },
              ];
        }),
      };
      return `<g class="band" ${tipAttributes(tip)}><rect x="${left}" y="${margin.top}" width="${right - left}" height="${height - margin.top - margin.bottom}" fill="transparent"/><line class="crosshair" x1="${x(size)}" x2="${x(size)}" y1="${margin.top}" y2="${height - margin.bottom}"/></g>`;
    })
    .join('');

  return `<figure class="chart"><figcaption>${escape(operation)}</figcaption><svg viewBox="0 0 ${width} ${height}" role="img" aria-label="${escape(`${operation}: time per call by size, for each implementation`)}">${grid}${xAxis}${series}${bands}</svg></figure>`;
};

/** The scaling charts, if any operation was measured at more than one size. */
const scalingSection = (benchmarks: Measured[]): string => {
  const sized = benchmarks.filter(
    ({implementation, size}) =>
      implementation !== undefined && size !== undefined,
  );
  const operations = [
    ...new Set(sized.map(({operation}) => operation!)),
  ].filter(
    (operation) =>
      new Set(
        sized
          .filter((benchmark) => benchmark.operation === operation)
          .map(({size}) => size),
      ).size > 1,
  );
  if (operations.length === 0) {
    return '';
  }
  const implementations = implementationsOf(sized);
  return `<section><h2>How time grows with size</h2><p class="note">Median time per call on log scales; faint dots are the individual processes. Hover a chart for the values.</p>${legend(implementations)}<div class="charts">${operations
    .map((operation) =>
      scalingChart(
        operation,
        sized.filter((benchmark) => benchmark.operation === operation),
        implementations,
      ),
    )
    .join('')}</div></section>`;
};

/**
 * A strip of a benchmark's processes, each a dot placed by its time relative
 * to their median, from 25% faster to 25% slower; beyond that it sits at the
 * edge.
 */
const strip = (name: string, averages: number[], spread: Spread): string => {
  const width = 96;
  const height = 16;
  const x = (average: number) =>
    4 +
    ((Math.min(Math.max(average / spread.median, 0.75), 1.25) - 0.75) / 0.5) *
      (width - 8);
  const tip: Tip = {
    title: name,
    rows: [...averages]
      .sort((a, b) => a - b)
      .map((average) => ({
        value: formatTime(average),
        label: formatPercent(average / spread.median - 1),
      })),
  };
  return `<svg class="strip" width="${width}" height="${height}" ${tipAttributes(tip)} role="img" aria-label="${escape(`${averages.length} processes, ${(spread.spread * 100).toFixed(1)}% apart`)}"><line class="grid" x1="${width / 2}" x2="${width / 2}" y1="2" y2="${height - 2}"/>${averages
    .map(
      (average) =>
        `<circle class="strip-dot${spread.noisy ? ' noisy' : ''}" cx="${x(average)}" cy="${height / 2}" r="3"/>`,
    )
    .join('')}</svg>`;
};

/** A table cell for one benchmark: its median, a strip, and a noisy mark. */
const measuredCell = (benchmark: Measured, fastest?: number): string =>
  `<td><span class="value">${escape(formatTime(benchmark.spread.median))}</span>${
    fastest === undefined
      ? ''
      : ` <span class="multiple">${(benchmark.spread.median / fastest).toFixed(2)}x</span>`
  }${benchmark.spread.noisy ? ' <span class="flag">noisy</span>' : ''}<br>${strip(benchmark.name, benchmark.averages, benchmark.spread)}</td>`;

/**
 * Every benchmark: those `Comparison` registered as an operation-by-
 * implementation table, the rest a row each.
 */
const tableSection = (benchmarks: Measured[]): string => {
  const compared = benchmarks.filter(
    ({implementation}) => implementation !== undefined,
  );
  const others = benchmarks.filter(
    ({implementation}) => implementation === undefined,
  );
  const implementations = implementationsOf(compared);
  const operations = [...new Set(compared.map(({operation}) => operation))];
  const groups = [...new Set(compared.map(({group}) => group!))].sort(
    (a, b) =>
      operations.indexOf(compared.find(({group}) => group === a)!.operation) -
      operations.indexOf(compared.find(({group}) => group === b)!.operation),
  );
  const pivot =
    compared.length === 0
      ? ''
      : `<table><thead><tr><th></th>${implementations
          .map((implementation) => `<th>${escape(implementation)}</th>`)
          .join('')}</tr></thead><tbody>${groups
          .map((group) => {
            const row = compared.filter(
              (benchmark) => benchmark.group === group,
            );
            const fastest = Math.min(...row.map(({spread}) => spread.median));
            return `<tr><th scope="row">${escape(group)}</th>${implementations
              .map((implementation) => {
                const benchmark = row.find(
                  (candidate) => candidate.implementation === implementation,
                );
                return benchmark === undefined
                  ? '<td></td>'
                  : measuredCell(benchmark, fastest);
              })
              .join('')}</tr>`;
          })
          .join('')}</tbody></table>`;
  const list =
    others.length === 0
      ? ''
      : `<table><thead><tr><th></th><th>median</th></tr></thead><tbody>${others
          .map(
            (benchmark) =>
              `<tr><th scope="row">${escape(benchmark.name)}</th>${measuredCell(benchmark)}</tr>`,
          )
          .join('')}</tbody></table>`;
  return `<section><h2>Every benchmark</h2><p class="note">Median time per call${
    compared.length === 0
      ? ''
      : ", with how many times the row's fastest median it is"
  }. Each strip shows the processes, from 25% faster than the median (left) to 25% slower (right); a benchmark is noisy when they landed more than ${noisySpread * 100}% apart.</p>${pivot}${list}</section>`;
};

/** A drawing of a change and its interval, from halving to doubling. */
const changeWidth = 220;

/** Where a ratio of times falls on the change drawing: half to double. */
const changeX = logScale(0.5, 2, 24, changeWidth - 24);

const changeBar = (
  estimate: number,
  low: number,
  high: number,
  verdict: string,
  tip: Tip,
): string => {
  const width = changeWidth;
  const height = 18;
  const x = (ratio: number) => changeX(Math.min(Math.max(ratio, 0.5), 2));
  const tone =
    verdict === 'faster' ? 'good' : verdict === 'slower' ? 'bad' : 'neutral';
  return `<svg class="change" width="${width}" height="${height}" ${tipAttributes(tip)} role="img" aria-label="${escape(`${tip.rows[0]!.value} ${tip.rows[0]!.label}`)}"><line class="axis" x1="${x(1)}" x2="${x(1)}" y1="0" y2="${height}"/><line class="interval ${tone}" x1="${x(low)}" x2="${x(high === Infinity ? 2 : high)}" y1="${height / 2}" y2="${height / 2}"/><circle class="estimate ${tone}" cx="${x(estimate)}" cy="${height / 2}" r="4"/></svg>`;
};

const changeAxis = (): string => {
  const x = changeX;
  return `<svg class="change" width="${changeWidth}" height="16" aria-hidden="true">${[
    0.5, 0.8, 1, 1.25, 2,
  ]
    .map(
      (ratio) =>
        `<text class="tick" x="${x(ratio)}" y="12" text-anchor="middle">${ratio === 1 ? '0' : formatPercent(ratio - 1).replace('.0', '')}</text>`,
    )
    .join('')}</svg>`;
};

/** Every benchmark both recordings measured: each side, and the change. */
const comparisonSection = (base: Recording, head: Recording): string => {
  const baseAverages = averagesByName(base);
  const headAverages = averagesByName(head);
  const rows = [...baseAverages]
    .filter(([name]) => headAverages.has(name))
    .map(([name, baseValues]) => {
      const headValues = headAverages.get(name)!;
      const {estimate, low, high} = change(baseValues, headValues);
      const verdict = high < 1 ? 'faster' : low > 1 ? 'slower' : '';
      const [baseSpread, headSpread] = [baseValues, headValues].map(spreadOf);
      const tip: Tip = {
        title: name,
        rows: [
          {
            value: formatPercent(estimate - 1),
            label:
              high === Infinity
                ? 'change, interval unbounded'
                : `change, ${formatPercent(low - 1)} to ${formatPercent(high - 1)}`,
          },
          {
            value: formatTime(baseSpread!.median),
            label: `base (${formatTime(baseSpread!.fastest)} to ${formatTime(baseSpread!.slowest)})`,
          },
          {
            value: formatTime(headSpread!.median),
            label: `head (${formatTime(headSpread!.fastest)} to ${formatTime(headSpread!.slowest)})`,
          },
        ],
      };
      return `<tr><th scope="row">${escape(name)}</th><td class="value">${escape(formatTime(baseSpread!.median))}</td><td class="value">${escape(formatTime(headSpread!.median))}</td><td class="value">${escape(formatPercent(estimate - 1))}</td><td class="interval-text">${
        high === Infinity
          ? 'unbounded'
          : escape(`${formatPercent(low - 1)} to ${formatPercent(high - 1)}`)
      }</td><td>${changeBar(estimate, low, high, verdict, tip)}</td><td>${
        verdict === ''
          ? ''
          : `<span class="verdict ${verdict === 'faster' ? 'good' : 'bad'}">${verdict === 'faster' ? '▼' : '▲'} ${verdict}</span>`
      }</td></tr>`;
    });
  return `<section><h2>What changed</h2><p class="note">The change is in time per call, base to head: negative is faster. A benchmark is called faster or slower only when its ${confidence * 100}% interval leaves out zero. The drawing runs from half the base's time to twice it.</p><table><thead><tr><th></th><th>base</th><th>head</th><th>change</th><th>${confidence * 100}% interval</th><th>${changeAxis()}</th><th></th></tr></thead><tbody>${rows.join('')}</tbody></table></section>`;
};

const describeSource = (recording: Recording): string => {
  const {source} = recording;
  const commit =
    source.commit.slice(0, 7) + (source.dirty ? ' with changes' : '');
  return source.label === source.commit.slice(0, 7) ||
    source.label === source.commit
    ? commit
    : `${source.label} (${commit})`;
};

const describeRun = (recording: Recording): string => {
  const count = Math.max(
    ...[...averagesByName(recording).values()].map(({length}) => length),
  );
  const environment = recording.environment;
  return `${recording.isolated ? `Each benchmark in ${count} processes of its own` : `${count} processes, each running every benchmark`}, ${new Date(recording.recordedAt).toLocaleString('en-US')}. Node ${environment.node} on ${environment.cpu}${environment.onBattery === true ? ', on battery' : ''}.`;
};

const styles = `
:root {
  color-scheme: light;
  --surface-1: #fcfcfb; --page: #f9f9f7;
  --text-primary: #0b0b0b; --text-secondary: #52514e; --text-muted: #898781;
  --grid: #e1e0d9; --axis: #c3c2b7; --border: rgba(11,11,11,0.10);
  --series-1: #2a78d6; --series-2: #eb6834; --series-3: #1baf7a; --series-4: #eda100;
  --series-5: #e87ba4; --series-6: #008300; --series-7: #4a3aa7; --series-8: #e34948;
  --good: #0ca30c; --good-text: #006300; --bad: #d03b3b; --neutral: #898781;
}
@media (prefers-color-scheme: dark) {
  :root:where(:not([data-theme="light"])) {
    color-scheme: dark;
    --surface-1: #1a1a19; --page: #0d0d0d;
    --text-primary: #ffffff; --text-secondary: #c3c2b7; --text-muted: #898781;
    --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10);
    --series-1: #3987e5; --series-2: #d95926; --series-3: #199e70; --series-4: #c98500;
    --series-5: #d55181; --series-6: #008300; --series-7: #9085e9; --series-8: #e66767;
    --good: #0ca30c; --good-text: #0ca30c; --bad: #d03b3b;
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --surface-1: #1a1a19; --page: #0d0d0d;
  --text-primary: #ffffff; --text-secondary: #c3c2b7; --text-muted: #898781;
  --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10);
  --series-1: #3987e5; --series-2: #d95926; --series-3: #199e70; --series-4: #c98500;
  --series-5: #d55181; --series-6: #008300; --series-7: #9085e9; --series-8: #e66767;
  --good: #0ca30c; --good-text: #0ca30c; --bad: #d03b3b;
}
* { box-sizing: border-box; }
html, body { margin: 0; background: var(--page); }
.viz-root {
  font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif;
  color: var(--text-primary); background: var(--page);
  max-width: 1200px; margin: 0 auto; padding: 24px 16px 48px;
}
h1 { font-size: 22px; font-weight: 600; margin: 0 0 4px; }
h2 { font-size: 16px; font-weight: 600; margin: 32px 0 4px; }
.subtitle, .note { color: var(--text-secondary); margin: 0 0 12px; }
.legend { list-style: none; display: flex; flex-wrap: wrap; gap: 4px 16px; padding: 0; margin: 0 0 12px; color: var(--text-secondary); }
.legend li, .tip-row { display: flex; align-items: center; gap: 6px; }
.charts { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 12px; }
.chart { margin: 0; padding: 12px; background: var(--surface-1); border: 1px solid var(--border); border-radius: 8px; }
.chart figcaption { font-weight: 600; margin-bottom: 4px; }
.chart svg { width: 100%; height: auto; display: block; overflow: visible; }
svg .grid { stroke: var(--grid); stroke-width: 1; }
svg .axis { stroke: var(--axis); stroke-width: 1; }
svg .tick { fill: var(--text-muted); font-size: 10px; font-variant-numeric: tabular-nums; }
svg .line { fill: none; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }
svg .marker { stroke: var(--surface-1); stroke-width: 2; }
svg .process { opacity: 0.35; }
svg .crosshair { stroke: var(--text-muted); stroke-width: 1; opacity: 0; }
.band:hover .crosshair, .band:focus .crosshair { opacity: 1; }
.band:focus, .strip:focus, .change:focus { outline: none; }
.strip:focus-visible, .band:focus-visible, .change:focus-visible { outline: 2px solid var(--series-1); }
.table-wrap { overflow-x: auto; }
table { border-collapse: collapse; background: var(--surface-1); border: 1px solid var(--border); border-radius: 8px; margin: 0 0 12px; font-variant-numeric: tabular-nums; }
th, td { padding: 6px 10px; text-align: right; vertical-align: top; border-bottom: 1px solid var(--grid); white-space: nowrap; }
th[scope="row"] { text-align: left; font-weight: 500; }
thead th { font-weight: 600; color: var(--text-secondary); }
.multiple { color: var(--text-muted); }
.flag { color: var(--text-secondary); font-size: 12px; }
.strip .strip-dot { fill: var(--text-muted); stroke: var(--surface-1); stroke-width: 1; }
.strip .strip-dot.noisy { fill: var(--text-primary); }
.change .interval { stroke-width: 2; stroke-linecap: round; }
.change .estimate { stroke: var(--surface-1); stroke-width: 2; }
.good { stroke: var(--good); fill: var(--good); }
.bad { stroke: var(--bad); fill: var(--bad); }
.neutral { stroke: var(--neutral); fill: var(--neutral); }
.verdict { font-weight: 600; stroke: none; }
.verdict.good { color: var(--good-text); fill: none; }
.verdict.bad { color: var(--bad); fill: none; }
.interval-text { color: var(--text-secondary); }
#tip { position: fixed; pointer-events: none; display: none; z-index: 1; background: var(--surface-1); border: 1px solid var(--border); border-radius: 6px; padding: 8px 10px; box-shadow: 0 4px 16px rgba(0,0,0,0.12); font-size: 13px; max-width: 360px; }
#tip .tip-title { color: var(--text-secondary); margin-bottom: 4px; }
#tip .tip-value { font-weight: 600; font-variant-numeric: tabular-nums; }
#tip .tip-label { color: var(--text-secondary); }
`;

// Builds each tooltip from its element's `data-tip` with `textContent` only:
// benchmark names come from benchmark programs, so they're never markup.
const script = `
const tip = document.getElementById('tip');
const show = (element, x, y) => {
  const data = JSON.parse(element.dataset.tip);
  tip.replaceChildren();
  const title = document.createElement('div');
  title.className = 'tip-title';
  title.textContent = data.title;
  tip.append(title);
  for (const row of data.rows) {
    const line = document.createElement('div');
    line.className = 'tip-row';
    if (row.series !== undefined) {
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('width', '16'); svg.setAttribute('height', '10');
      const key = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      for (const [name, value] of [['x1', 1], ['y1', 5], ['x2', 15], ['y2', 5], ['stroke-width', 2], ['stroke-linecap', 'round']]) key.setAttribute(name, value);
      key.setAttribute('stroke', 'var(--series-' + row.series + ')');
      svg.append(key);
      line.append(svg);
    }
    const value = document.createElement('span');
    value.className = 'tip-value';
    value.textContent = row.value;
    const label = document.createElement('span');
    label.className = 'tip-label';
    label.textContent = row.label;
    line.append(value, label);
    tip.append(line);
  }
  tip.style.display = 'block';
  const {width, height} = tip.getBoundingClientRect();
  tip.style.left = Math.min(x + 14, innerWidth - width - 8) + 'px';
  tip.style.top = Math.min(y + 14, innerHeight - height - 8) + 'px';
};
const hide = () => { tip.style.display = 'none'; };
for (const element of document.querySelectorAll('[data-tip]')) {
  element.addEventListener('pointermove', (event) => show(element, event.clientX, event.clientY));
  element.addEventListener('pointerleave', hide);
  element.addEventListener('focus', () => {
    const box = element.getBoundingClientRect();
    show(element, box.right, box.top);
  });
  element.addEventListener('blur', hide);
}
`;

const page = (title: string, subtitle: string, body: string): string =>
  `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title>
<style>${styles}</style>
</head>
<body>
<main class="viz-root">
<h1>${escape(title)}</h1>
<p class="subtitle">${subtitle}</p>
${body}
<div id="tip" role="tooltip"></div>
</main>
<script>${script}</script>
</body>
</html>
`;

/** A page exploring one recording. */
export const recordingPage = (recording: Recording): string => {
  const benchmarks = measured(recording);
  return page(
    `${recording.package} (${recording.entry})`,
    `${escape(describeSource(recording))}. ${escape(describeRun(recording))}`,
    `${scalingSection(benchmarks)}<div class="table-wrap">${tableSection(benchmarks)}</div>`,
  );
};

/** A page comparing two recordings of the same benchmarks. */
export const comparisonPage = (base: Recording, head: Recording): string =>
  page(
    `${head.package} (${head.entry}): ${describeSource(base)} to ${describeSource(head)}`,
    `Base: ${escape(describeRun(base))}<br>Head: ${escape(describeRun(head))}`,
    `<div class="table-wrap">${comparisonSection(base, head)}</div>`,
  );
