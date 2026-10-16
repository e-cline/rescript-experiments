/**
 * What `res-bench` records: one benchmark bundle's measurements over several
 * processes, with enough about where and how they were taken to tell whether
 * two recordings can be compared.
 */
import {execFileSync, spawn} from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import {createRequire} from 'node:module';
import {cpus, platform, tmpdir, totalmem} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

/** One benchmark's measurements in one process, in nanoseconds per call. */
export type Measurement = {
  name: string;
  /**
   * The mitata group the benchmark was registered in, if any. Absent from
   * recordings made before `res-bench` recorded it.
   */
  group?: string;
  avg: number;
  min: number;
  p50: number;
  p75: number;
  p99: number;
  max: number;
  /** How many samples mitata took. */
  samples: number;
};

/** What one process recorded: mitata's `run` resolves to it. */
export type ProcessResult = {
  benchmarks: (Measurement | {name: string; error: string})[];
};

/** The code that was measured. */
export type Source = {
  /** How it was asked for: a git ref, or `"working tree"`. */
  label: string;
  commit: string;
  /** Whether the working tree had uncommitted changes. Always false for a ref. */
  dirty: boolean;
};

export type Environment = {
  node: string;
  v8: string;
  platform: string;
  arch: string;
  cpu: string;
  cores: number;
  memoryGiB: number;
  /** `null` where it couldn't be determined (anything but macOS, so far). */
  onBattery: boolean | null;
  lowPowerMode: boolean | null;
  mitata: string;
};

export type Recording = {
  version: 1;
  recordedAt: string;
  /** The benchmark package's directory, relative to the repository root. */
  package: string;
  /** The bundle's name in the package's `dist/`, without `.js`. */
  entry: string;
  filter: string | null;
  /**
   * Whether each benchmark ran in processes of its own, rather than every
   * process running all of them.
   */
  isolated: boolean;
  source: Source;
  environment: Environment;
  processes: ProcessResult[];
};

const require = createRequire(import.meta.url);

const commandOutput = (command: string, args: string[]): string | null => {
  try {
    return execFileSync(command, args, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch {
    return null;
  }
};

export const environment = (): Environment => {
  const darwin = platform() === 'darwin';
  const battery = darwin ? commandOutput('pmset', ['-g', 'batt']) : null;
  const settings = darwin ? commandOutput('pmset', ['-g']) : null;
  return {
    node: process.version,
    v8: process.versions.v8,
    platform: platform(),
    arch: process.arch,
    cpu: cpus()[0]?.model ?? 'unknown',
    cores: cpus().length,
    memoryGiB: Math.round(totalmem() / 2 ** 30),
    onBattery: battery === null ? null : battery.includes("'Battery Power'"),
    lowPowerMode:
      settings === null ? null : /\blowpowermode\s+1\b/.test(settings),
    mitata: (
      JSON.parse(
        readFileSync(require.resolve('mitata/package.json'), 'utf8'),
      ) as {version: string}
    ).version,
  };
};

/** Warnings worth printing before measuring anything in `environment`. */
export const environmentWarnings = (env: Environment): string[] => [
  ...(env.onBattery === true
    ? ['Running on battery power, which can throttle the CPU.']
    : []),
  ...(env.lowPowerMode === true
    ? ['Low Power Mode is on, which throttles the CPU.']
    : []),
];

const register = pathToFileURL(
  join(import.meta.dirname, 'capture', 'register.mjs'),
).href;

let processCount = 0;

/**
 * Runs `bundle` in a process of its own, with `env` added to the environment,
 * and returns what it wrote to `RES_BENCH_OUTPUT` (see `capture/mitata.mjs`).
 * The process's own output is discarded; its error output is shown only if it
 * fails.
 */
const runBundle = async (
  bundle: string,
  filter: string | null,
  env: Record<string, string>,
): Promise<unknown> => {
  processCount += 1;
  const output = join(
    tmpdir(),
    `res-bench-${process.pid}-${processCount}.json`,
  );
  const child = spawn(
    process.execPath,
    // `--expose-gc` lets mitata collect garbage between benchmarks, as the
    // packages' own `bench` tasks do.
    [
      '--expose-gc',
      '--import',
      register,
      bundle,
      ...(filter === null ? [] : [filter]),
    ],
    {
      stdio: ['ignore', 'ignore', 'pipe'],
      env: {...process.env, ...env, RES_BENCH_OUTPUT: output},
    },
  );
  let errorOutput = '';
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', (chunk: string) => {
    errorOutput += chunk;
  });
  const exitCode = await new Promise<number | null>((resolve, reject) => {
    child.on('error', reject);
    child.on('close', resolve);
  });
  if (exitCode !== 0) {
    throw new Error(
      `${bundle} exited with code ${exitCode}:\n${errorOutput.trimEnd()}`,
    );
  }
  if (!existsSync(output)) {
    throw new Error(
      `${bundle} exited without recording anything. Does it run its benchmarks with mitata's \`run\`?`,
    );
  }
  const result: unknown = JSON.parse(readFileSync(output, 'utf8'));
  rmSync(output);
  return result;
};

/**
 * Runs `bundle` once, in a process of its own, and returns what it measured.
 */
export const measureProcess = async (
  bundle: string,
  filter: string | null,
): Promise<ProcessResult> =>
  (await runBundle(bundle, filter, {})) as ProcessResult;

/** The name of every benchmark `bundle` registers, in the order it does. */
export const benchmarkNames = async (bundle: string): Promise<string[]> =>
  ((await runBundle(bundle, null, {RES_BENCH_LIST: '1'})) as {names: string[]})
    .names;

const regExpSyntax = /[.*+?^${}()|[\]\\]/g;

/** A filter selecting the benchmark called `name` and nothing else. */
export const exactly = (name: string): string =>
  `^${name.replace(regExpSyntax, '\\$&')}$`;

const timestamp = (date: Date): string =>
  date.toISOString().slice(0, 19).replaceAll(':', '-');

/**
 * Writes `recording` to `.bench/results/` under the repository root and returns
 * the file's path.
 */
export const save = (repoRoot: string, recording: Recording): string => {
  const directory = join(repoRoot, '.bench', 'results');
  mkdirSync(directory, {recursive: true});
  const file = join(
    directory,
    [
      timestamp(new Date(recording.recordedAt)),
      recording.package.replaceAll('/', '_'),
      recording.entry,
      recording.source.commit.slice(0, 7) +
        (recording.source.dirty ? '-dirty' : ''),
    ].join('_') + '.json',
  );
  writeFileSync(file, JSON.stringify(recording, null, 2) + '\n');
  return file;
};

export const load = (file: string): Recording => {
  const recording = JSON.parse(readFileSync(file, 'utf8')) as Recording;
  if (recording.version !== 1) {
    throw new Error(`${file} isn't a res-bench recording this version reads.`);
  }
  return recording;
};

/**
 * Each benchmark's per-call average in every process that measured it, in the
 * order the benchmarks were first registered.
 */
export const averagesByName = (recording: Recording): Map<string, number[]> => {
  const averages = new Map<string, number[]>();
  for (const {benchmarks} of recording.processes) {
    for (const benchmark of benchmarks) {
      if ('avg' in benchmark) {
        const existing = averages.get(benchmark.name);
        if (existing === undefined) {
          averages.set(benchmark.name, [benchmark.avg]);
        } else {
          existing.push(benchmark.avg);
        }
      }
    }
  }
  return averages;
};

/** Every distinct error any process recorded, as `"name: message"`. */
export const errors = (recording: Recording): string[] => [
  ...new Set(
    recording.processes.flatMap(({benchmarks}) =>
      benchmarks.flatMap((benchmark) =>
        'error' in benchmark ? [`${benchmark.name}: ${benchmark.error}`] : [],
      ),
    ),
  ),
];

/**
 * What a benchmark's name and group say about it. `Comparison` names each of
 * its benchmarks `<implementation>.<group>`, with groups like `get n=1000`, so
 * for those the implementation, the operation, and the size it was measured at
 * can be read off; other benchmarks have only a name, and perhaps a group.
 */
export type Identity = {
  name: string;
  group?: string;
  implementation?: string;
  /** The group without its parameter: `get`. */
  operation?: string;
  /** The group's last word, if it's `<key>=<value>`: `n=1000`. */
  parameter?: string;
  /** The parameter's value, if it's a number: what scaling charts plot against. */
  size?: number;
};

const parameterPattern = /^\S+=(\S+)$/;

/** Every benchmark's identity, in the order the benchmarks were registered. */
export const identities = (recording: Recording): Map<string, Identity> => {
  const result = new Map<string, Identity>();
  for (const {benchmarks} of recording.processes) {
    for (const benchmark of benchmarks) {
      if (result.has(benchmark.name)) {
        continue;
      }
      const group = 'group' in benchmark ? benchmark.group : undefined;
      if (group === undefined || !benchmark.name.endsWith(`.${group}`)) {
        result.set(benchmark.name, {name: benchmark.name, group});
        continue;
      }
      const words = group.split(' ');
      const last = words.at(-1)!;
      const match = words.length > 1 ? parameterPattern.exec(last) : null;
      const value = match === null ? NaN : Number(match[1]);
      result.set(benchmark.name, {
        name: benchmark.name,
        group,
        implementation: benchmark.name.slice(0, -group.length - 1),
        operation: match === null ? group : words.slice(0, -1).join(' '),
        ...(match === null ? {} : {parameter: last}),
        ...(Number.isFinite(value) ? {size: value} : {}),
      });
    }
  }
  return result;
};
