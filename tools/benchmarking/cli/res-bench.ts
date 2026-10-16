#!/usr/bin/env node
/**
 * `res-bench`: runs a benchmark package's bundle in several processes, records
 * the results, and compares recordings. See this package's README.
 */
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import {basename, join, relative} from 'node:path';
import {parseArgs} from 'node:util';

import type {Build} from './build.ts';
import {cleanups, git, refBuild, workingTreeBuild} from './build.ts';
import {comparisonPage, recordingPage} from './html.ts';
import {fill} from './readme.ts';
import {
  comparison,
  environmentDifferences,
  formatTime,
  summary,
} from './report.ts';
import type {ProcessResult, Recording} from './results.ts';
import {
  benchmarkNames,
  environment,
  environmentWarnings,
  errors,
  exactly,
  load,
  measureProcess,
  save,
} from './results.ts';

/**
 * `--budget`'s default, in milliseconds: mitata's own. Shorter budgets measure
 * some benchmarks slower: at 200 ms, `get n=10000` came out 15-20% slower,
 * every sample of it, not just the first.
 */
const defaultBudgetMs = 642;

const usage = `Usage, from a benchmark package's directory:

  res-bench run [<filter>] [--processes <n>] [--budget <ms>] [--entry <name>] [--shared]
      Runs each benchmark in the package's dist/<name>.js in <n> fresh
      processes of its own (default 5), prints each one's median and spread,
      and saves the results.

  res-bench compare <base> [<head>] [--filter <regexp>] [--processes <n>] [--budget <ms>] [--entry <name>] [--shared]
      Builds the package at the git ref <base>, and at <head> (default: the
      working tree's dist/), then runs the two alternately, <n> processes each
      per benchmark (default 5), and prints how each benchmark changed.

--shared runs every benchmark in each process instead, one after another, as
the packages' own \`bench\` tasks do: quicker if their setup is slow, but
each benchmark's time then depends on the ones before it.

--budget is how long mitata samples each benchmark for in each process, in
milliseconds of measured time (default ${defaultBudgetMs}, mitata's own).
Shorter is quicker, but measures some benchmarks slower, so compare only
recordings made with the same budget.

  res-bench check [--filter <regexp>] [--budget <ms>] [--entry <name>]
      Checks that the package's dist/<name>.js still runs under res-bench:
      lists its benchmarks, and measures one (the first, or the first the
      filter selects) in a process of its own. Saves nothing.

Anywhere:

  res-bench show <recording.json>
  res-bench diff <base.json> <head.json>
      Prints a saved recording, or compares two. Recordings are saved in
      .bench/results/ at the repository root.

  res-bench report <recording.json> [<head.json>]
      Writes an HTML page exploring a recording, or comparing two, to
      .bench/reports/. run and compare write one for what they recorded.

  res-bench readme <file.md>... [--from <recording.json>] [--entry <name>]
      Fills every block in each <file.md> marked
        <!-- res-bench filter="<regexp>" --> ... <!-- /res-bench -->
      with a table of the recording's benchmarks the filter selects. The
      recording defaults to the newest one of this package's <entry>.

<entry> defaults to "bench". A filter is a regular expression selecting
benchmarks by name, as the packages' own \`bench\` tasks take.`;

const {values: options, positionals} = parseArgs({
  allowPositionals: true,
  options: {
    processes: {type: 'string', short: 'n'},
    budget: {type: 'string'},
    entry: {type: 'string', default: 'bench'},
    filter: {type: 'string'},
    from: {type: 'string'},
    shared: {type: 'boolean', default: false},
    help: {type: 'boolean', short: 'h'},
  },
});

const fail = (message: string): never => {
  console.error(message);
  process.exit(1);
};

const processCount = (fallback: number): number => {
  if (options.processes === undefined) {
    return fallback;
  }
  const count = Number(options.processes);
  return Number.isInteger(count) && count > 0
    ? count
    : fail('--processes takes a positive whole number.');
};

const budgetMs = (): number => {
  if (options.budget === undefined) {
    return defaultBudgetMs;
  }
  const budget = Number(options.budget);
  return Number.isFinite(budget) && budget > 0
    ? budget
    : fail('--budget takes a positive number of milliseconds.');
};

const repoRoot = (): string => git(['rev-parse', '--show-toplevel'], '.');

/**
 * Writes `html` to `.bench/reports/<name>.html` under the repository root and
 * returns the file's path.
 */
const writeReport = (root: string, name: string, html: string): string => {
  const directory = join(root, '.bench', 'reports');
  mkdirSync(directory, {recursive: true});
  const file = join(directory, `${name}.html`);
  writeFileSync(file, html);
  return file;
};

/**
 * The most recently recorded of the saved recordings of `packagePath`'s
 * `entry`, if there are any.
 */
const newestRecording = (
  root: string,
  packagePath: string,
  entry: string,
): string | undefined => {
  const directory = join(root, '.bench', 'results');
  if (!existsSync(directory)) {
    return undefined;
  }
  return readdirSync(directory)
    .filter((name) => name.endsWith('.json'))
    .map((name) => join(directory, name))
    .map((file) => ({file, recording: load(file)}))
    .filter(
      ({recording}) =>
        recording.package === packagePath && recording.entry === entry,
    )
    .sort((a, b) =>
      a.recording.recordedAt.localeCompare(b.recording.recordedAt),
    )
    .at(-1)?.file;
};

/** A recording file's name, without its directory or `.json`. */
const stem = (file: string): string => basename(file, '.json');

const seconds = (since: number): string =>
  `${((performance.now() - since) / 1e3).toFixed(1)}s`;

const record = (
  build: Build,
  packagePath: string,
  filter: string | null,
  processes: ProcessResult[],
): Recording => ({
  version: 1,
  recordedAt: new Date().toISOString(),
  package: packagePath,
  entry: options.entry,
  filter,
  isolated: !options.shared,
  budgetMs: budgetMs(),
  source: build.source,
  environment: environment(),
  processes,
});

/** Ends the run, listing them, if a benchmark threw in any of `recordings`. */
const failOnErrors = (...recordings: Recording[]) => {
  const all = [...new Set(recordings.flatMap(errors))];
  if (all.length > 0) {
    fail(`Some benchmarks threw:\n${all.join('\n')}`);
  }
};

/**
 * The names of the benchmarks to run, from every one of `bundles`: those the
 * first registers, in the order it does, then any only a later one has. Also
 * which of them each bundle has.
 */
const namesToRun = async (
  bundles: string[],
  filter: string | null,
): Promise<{names: string[]; has: Set<string>[]}> => {
  const has = [];
  for (const bundle of bundles) {
    has.push(new Set(await benchmarkNames(bundle)));
  }
  const selected = filter === null ? null : new RegExp(filter);
  const names = [...new Set(has.flatMap((names) => [...names]))].filter(
    (name) => selected === null || selected.test(name),
  );
  return names.length > 0
    ? {names, has}
    : fail(`No benchmark's name matches ${filter}.`);
};

/**
 * Runs each of `builds` `count` times and returns what each measured, one
 * process at a time. Unless `--shared` was given, each benchmark runs in
 * processes of its own: `count` for each build that has it.
 */
const measure = async (
  builds: {name: string; build: Build}[],
  count: number,
  filter: string | null,
): Promise<ProcessResult[][]> => {
  const bundles = builds.map(({build}) => {
    const bundle = join(build.directory, `${options.entry}.js`);
    return existsSync(bundle)
      ? bundle
      : fail(
          `The ${build.source.label} build has no ${options.entry}.js (see --entry).`,
        );
  });
  for (const warning of environmentWarnings(environment())) {
    console.warn(`Warning: ${warning}`);
  }
  const results: ProcessResult[][] = builds.map(() => []);

  if (!options.shared) {
    const {names, has} = await namesToRun(bundles, filter);
    console.log(
      `Running each of ${names.length} ${names.length === 1 ? 'benchmark' : 'benchmarks'} in ${count} processes of its own${builds.length > 1 ? ' on each side' : ''}.`,
    );
    for (let round = 0; round < count; round++) {
      const started = performance.now();
      for (const [position, name] of names.entries()) {
        // Alternating which side goes first, from one benchmark to the next
        // and from one round to the next, cancels out whatever drifts over
        // the run (the machine warming up, something starting in the
        // background) instead of charging it all to whichever side always
        // runs second.
        const order = builds
          .map((_, index) => index)
          .filter((index) => has[index]!.has(name));
        if ((round + position) % 2 === 1) {
          order.reverse();
        }
        for (const index of order) {
          results[index]!.push(
            await measureProcess(bundles[index]!, exactly(name), budgetMs()),
          );
        }
      }
      console.log(`round ${round + 1}/${count}: ${seconds(started)}`);
    }
    return results;
  }

  const total = builds.length * count;
  let done = 0;
  for (let round = 0; round < count; round++) {
    // Alternating the order, as above.
    const order = builds.map((_, index) => index);
    if (round % 2 === 1) {
      order.reverse();
    }
    for (const index of order) {
      const started = performance.now();
      results[index]!.push(
        await measureProcess(bundles[index]!, filter, budgetMs()),
      );
      done += 1;
      console.log(
        `process ${done}/${total}${builds.length > 1 ? ` (${builds[index]!.name})` : ''}: ${seconds(started)}`,
      );
    }
  }
  return results;
};

const commands: Record<string, () => Promise<void>> = {
  run: async () => {
    if (positionals.length > 1) {
      fail(usage);
    }
    const root = repoRoot();
    const packagePath = relative(root, process.cwd());
    const filter = positionals[0] ?? options.filter ?? null;
    const build = workingTreeBuild(root, process.cwd());
    const [processes] = await measure(
      [{name: 'working tree', build}],
      processCount(5),
      filter,
    );
    const recording = record(build, packagePath, filter, processes!);
    failOnErrors(recording);
    const file = save(root, recording);
    const report = writeReport(root, stem(file), recordingPage(recording));
    console.log(
      `\n${summary(recording)}\n\nSaved to ${relative('.', file)}\nReport: ${relative('.', report)}`,
    );
  },

  compare: async () => {
    if (positionals.length < 1 || positionals.length > 2) {
      fail(usage);
    }
    const [baseRef, headRef] = positionals;
    const root = repoRoot();
    const packagePath = relative(root, process.cwd());
    const filter = options.filter ?? null;
    const base = refBuild(root, packagePath, baseRef!);
    const head =
      headRef === undefined
        ? workingTreeBuild(root, process.cwd())
        : refBuild(root, packagePath, headRef);
    const [baseProcesses, headProcesses] = await measure(
      [
        {name: 'base', build: base},
        {name: 'head', build: head},
      ],
      processCount(5),
      filter,
    );
    const baseRecording = record(base, packagePath, filter, baseProcesses!);
    const headRecording = record(head, packagePath, filter, headProcesses!);
    failOnErrors(baseRecording, headRecording);
    const files = [save(root, baseRecording), save(root, headRecording)];
    const report = writeReport(
      root,
      `${stem(files[1]!)}_compared`,
      comparisonPage(baseRecording, headRecording),
    );
    console.log(
      `\n${comparison(baseRecording, headRecording)}\n\nSaved to ${files.map((file) => relative('.', file)).join(' and ')}\nReport: ${relative('.', report)}`,
    );
  },

  check: async () => {
    if (positionals.length > 0) {
      fail(usage);
    }
    const bundle = join(process.cwd(), 'dist', `${options.entry}.js`);
    if (!existsSync(bundle)) {
      fail(`${relative('.', bundle)} doesn't exist. Build the package first.`);
    }
    const names = await benchmarkNames(bundle);
    const selected =
      options.filter === undefined ? null : new RegExp(options.filter);
    const name =
      names.find(
        (candidate) => selected === null || selected.test(candidate),
      ) ??
      fail(
        names.length === 0
          ? `${relative('.', bundle)} registers no benchmarks.`
          : `No benchmark's name matches ${options.filter}.`,
      );
    const {benchmarks} = await measureProcess(
      bundle,
      exactly(name),
      budgetMs(),
    );
    const result = benchmarks.find((benchmark) => benchmark.name === name);
    if (result === undefined || !('avg' in result)) {
      fail(
        result === undefined
          ? `${name} ran, but nothing was recorded for it.`
          : `${name} threw: ${result.error}`,
      );
    }
    console.log(
      `${relative('.', bundle)}: ${names.length} benchmarks; ${name} measured at ${formatTime((result as {avg: number}).avg)} per call.`,
    );
  },

  show: async () => {
    if (positionals.length !== 1) {
      fail(usage);
    }
    console.log(summary(load(positionals[0]!)));
  },

  report: async () => {
    if (positionals.length < 1 || positionals.length > 2) {
      fail(usage);
    }
    const [base, head] = positionals.map(load);
    const report =
      head === undefined
        ? writeReport(repoRoot(), stem(positionals[0]!), recordingPage(base!))
        : writeReport(
            repoRoot(),
            `${stem(positionals[1]!)}_compared`,
            comparisonPage(base!, head),
          );
    console.log(relative('.', report));
  },

  readme: async () => {
    if (positionals.length === 0) {
      fail(usage);
    }
    const root = repoRoot();
    const recordingFile =
      options.from ??
      newestRecording(root, relative(root, process.cwd()), options.entry) ??
      fail(
        `No recording of ${relative(root, process.cwd())} (${options.entry}) in .bench/results/. Record one with \`vp run bench:record\`, or name one with --from.`,
      );
    const recording = load(recordingFile);
    // Every file is filled before any is written, so that a mistake in one
    // leaves them all as they were.
    const filled = positionals.map((file) => {
      const {markdown, blocks} = fill(
        readFileSync(file, 'utf8'),
        recording,
        file,
      );
      return blocks === 0
        ? fail(`${file} has no <!-- res-bench filter="..." --> blocks.`)
        : {file, markdown, blocks};
    });
    for (const {file, markdown, blocks} of filled) {
      writeFileSync(file, markdown);
      console.log(
        `Filled ${blocks} ${blocks === 1 ? 'block' : 'blocks'} in ${file}.`,
      );
    }
    console.log(`From ${relative('.', recordingFile)}`);
  },

  diff: async () => {
    if (positionals.length !== 2) {
      fail(usage);
    }
    const [base, head] = positionals.map(load) as [Recording, Recording];
    for (const difference of environmentDifferences(base, head)) {
      console.warn(`Warning: ${difference}`);
    }
    console.log(comparison(base, head));
    console.log(
      '\nUnless these two were recorded together by `compare`, anything that changed on the machine between them counts as a change here.',
    );
  },
};

const command = positionals.shift();
if (options.help || command === undefined || !(command in commands)) {
  console.log(usage);
  process.exit(options.help ? 0 : 1);
}

const runCleanups = () => {
  for (const cleanup of cleanups) {
    cleanup();
  }
  cleanups.clear();
};
process.on('exit', runCleanups);
process.on('SIGINT', () => process.exit(130));
process.on('SIGTERM', () => process.exit(143));

try {
  await commands[command]!();
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
