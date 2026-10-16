import type {Spread} from './report.ts';
import {formatTime, noisySpread, spreadOf} from './report.ts';
/**
 * `res-bench readme`: keeping the measurements in a Markdown file current.
 *
 * A file marks where a table goes, and which benchmarks it shows, with a pair
 * of comments:
 *
 *     <!-- res-bench filter="\.get n=" -->
 *     <!-- /res-bench -->
 *
 * `fill` replaces whatever is between each pair with a table of the matching
 * benchmarks from a recording, and a line saying where and how they were
 * measured. Prose summarizing the numbers stays hand-written; the numbers it
 * summarizes are the part that goes stale.
 *
 * `filter` is a regular expression on benchmark names, as everywhere else in
 * `res-bench`. Benchmarks registered through `Comparison` are shown an
 * implementation to a column, each time followed by its multiple of the row's
 * fastest, or of the implementation `relative="<name>"` names. Any others are
 * listed with their median and spread.
 */
import type {Recording} from './results.ts';
import {averagesByName, identities} from './results.ts';

const opening = /<!--\s*res-bench\b([^>]*?)-->/g;
const closing = /<!--\s*\/res-bench\s*-->/;
const attribute = /(\w+)="((?:[^"\\]|\\.)*)"/g;

type Block = {filter: RegExp; relative: string | undefined};

const parseAttributes = (text: string, where: string): Block => {
  const attributes = new Map<string, string>();
  for (const [, name, value] of text.matchAll(attribute)) {
    attributes.set(name!, value!.replaceAll('\\"', '"'));
  }
  for (const name of attributes.keys()) {
    if (name !== 'filter' && name !== 'relative') {
      throw new Error(`${where}: unknown attribute ${name}.`);
    }
  }
  const filter = attributes.get('filter');
  if (filter === undefined) {
    throw new Error(`${where}: needs a filter="..." attribute.`);
  }
  return {filter: new RegExp(filter), relative: attributes.get('relative')};
};

/** A Markdown table: the first column left-aligned, the rest right-aligned. */
const markdownTable = (rows: string[][]): string => {
  const widths = rows[0]!.map((_, column) =>
    Math.max(3, ...rows.map((row) => row[column]?.length ?? 0)),
  );
  const line = (row: string[]) =>
    `| ${row
      .map((cell, column) =>
        column === 0
          ? cell.padEnd(widths[column]!)
          : cell.padStart(widths[column]!),
      )
      .join(' | ')} |`;
  const rule = `| ${widths
    .map((width, column) =>
      column === 0 ? '-'.repeat(width) : `${'-'.repeat(width - 1)}:`,
    )
    .join(' | ')} |`;
  return [line(rows[0]!), rule, ...rows.slice(1).map(line)].join('\n');
};

/** Backslash-escapes what Markdown would read as table syntax or emphasis. */
const cell = (text: string): string => text.replace(/([|*_`\\])/g, '\\$1');

const timeCell = (spread: Spread): string =>
  `${formatTime(spread.median)}${spread.noisy ? '\\*' : ''}`;

/**
 * The tables for one block, and whether one of them has multiples in brackets.
 * Throws if nothing matches the block's filter.
 */
const blockTables = (
  recording: Recording,
  block: Block,
): {tables: string; multiples: boolean} => {
  const averages = averagesByName(recording);
  const selected = [...identities(recording).values()].filter(
    ({name}) => averages.has(name) && block.filter.test(name),
  );
  if (selected.length === 0) {
    throw new Error(`No benchmark in the recording matches ${block.filter}.`);
  }
  const spreads = new Map(
    selected.map(({name}) => [name, spreadOf(averages.get(name)!)]),
  );
  const compared = selected.filter(
    ({implementation}) => implementation !== undefined,
  );
  const others = selected.filter(
    ({implementation}) => implementation === undefined,
  );
  const tables: string[] = [];

  if (compared.length > 0) {
    const implementations = [
      ...new Set(compared.map(({implementation}) => implementation!)),
    ];
    if (
      block.relative !== undefined &&
      !implementations.includes(block.relative)
    ) {
      throw new Error(
        `relative="${block.relative}" names none of the implementations the filter selects: ${implementations.join(', ')}.`,
      );
    }
    const operations = [...new Set(compared.map(({operation}) => operation))];
    const groups = [...new Set(compared.map(({group}) => group!))].sort(
      (a, b) =>
        operations.indexOf(compared.find(({group}) => group === a)!.operation) -
        operations.indexOf(compared.find(({group}) => group === b)!.operation),
    );
    const rows = [['', ...implementations.map(cell)]];
    for (const group of groups) {
      const inGroup = compared.filter((identity) => identity.group === group);
      const medianOf = (implementation: string) => {
        const identity = inGroup.find(
          (candidate) => candidate.implementation === implementation,
        );
        return identity === undefined ? undefined : spreads.get(identity.name)!;
      };
      const reference =
        block.relative === undefined
          ? Math.min(...inGroup.map(({name}) => spreads.get(name)!.median))
          : medianOf(block.relative)?.median;
      rows.push([
        cell(group),
        ...implementations.map((implementation) => {
          const spread = medianOf(implementation);
          return spread === undefined
            ? ''
            : reference === undefined
              ? timeCell(spread)
              : `${timeCell(spread)} (${(spread.median / reference).toFixed(2)}x)`;
        }),
      ]);
    }
    tables.push(markdownTable(rows));
  }

  if (others.length > 0) {
    tables.push(
      markdownTable([
        ['', 'median', 'fastest', 'slowest'],
        ...others.map(({name}) => {
          const spread = spreads.get(name)!;
          return [
            cell(name),
            timeCell(spread),
            formatTime(spread.fastest),
            formatTime(spread.slowest),
          ];
        }),
      ]),
    );
  }
  return {tables: tables.join('\n\n'), multiples: compared.length > 0};
};

/**
 * The column Markdown prose wraps at in this repository (see the root
 * vite.config.ts's `fmt` settings). Prose `fill` writes is wrapped the way the
 * formatter would, so that formatting a filled file changes nothing.
 */
const proseWidth = 100;

/** `text`'s words, as many to a line as fit in `proseWidth`. */
const wrap = (text: string): string => {
  const lines: string[] = [];
  let line = '';
  for (const word of text.split(' ')) {
    if (line !== '' && line.length + 1 + word.length > proseWidth) {
      lines.push(line);
      line = word;
    } else {
      line = line === '' ? word : `${line} ${word}`;
    }
  }
  return [...lines, line].join('\n');
};

/** Where and how the recording was made. */
const provenance = (
  recording: Recording,
  block: Block,
  multiples: boolean,
  anyNoisy: boolean,
): string => {
  const {source, environment} = recording;
  const count = Math.max(
    ...[...averagesByName(recording).values()].map(({length}) => length),
  );
  const brackets = !multiples
    ? ''
    : block.relative === undefined
      ? " In brackets, each time's multiple of the fastest in its row."
      : ` In brackets, each time's multiple of ${block.relative}'s.`;
  return wrap(
    [
      `Median time per call.${brackets}${anyNoisy ? ` \\* marks a benchmark whose processes landed more than ${noisySpread * 100}% apart.` : ''}`,
      `Measured at ${source.commit.slice(0, 7)}${source.dirty ? ' with uncommitted changes' : ''}, ${recording.isolated ? `each benchmark in ${count} processes of its own` : `in ${count} processes`}, with Node ${environment.node} on ${environment.cpu}, ${recording.recordedAt.slice(0, 10)}.`,
    ].join(' '),
  );
};

/**
 * `markdown` with every marked block filled in from `recording`. Throws,
 * naming the line, if a block is malformed or matches nothing.
 */
export const fill = (
  markdown: string,
  recording: Recording,
  file: string,
): {markdown: string; blocks: number} => {
  let result = '';
  let rest = markdown;
  let offset = 0;
  let blocks = 0;
  for (;;) {
    opening.lastIndex = 0;
    const start = opening.exec(rest);
    if (start === null) {
      return {markdown: result + rest, blocks};
    }
    const line = markdown.slice(0, offset + start.index).split('\n').length;
    const where = `${file}:${line}`;
    const afterOpening = start.index + start[0].length;
    const end = closing.exec(rest.slice(afterOpening));
    if (end === null) {
      throw new Error(`${where}: no <!-- /res-bench --> closes this block.`);
    }
    const block = parseAttributes(start[1]!, where);
    let filled: {tables: string; multiples: boolean};
    try {
      filled = blockTables(recording, block);
    } catch (error) {
      throw new Error(`${where}: ${(error as Error).message}`);
    }
    const anyNoisy = filled.tables.includes('\\*');
    result +=
      rest.slice(0, afterOpening) +
      `\n\n${filled.tables}\n\n${provenance(recording, block, filled.multiples, anyNoisy)}\n\n`;
    const closingStart = afterOpening + end.index;
    offset += closingStart;
    rest = rest.slice(closingStart);
    // Step past the closing comment's start so the next search can't find
    // this block's opening again.
    result += rest.slice(0, end[0].length);
    offset += end[0].length;
    rest = rest.slice(end[0].length);
    blocks += 1;
  }
};
