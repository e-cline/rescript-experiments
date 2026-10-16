// What a benchmark bundle gets when it imports `mitata` in a process `res-bench`
// started (see `register.mjs`): mitata itself, except for `bench`, which also
// keeps each benchmark it registers, and `run`, which runs them itself, prints
// nothing, and writes what they measured to the file named by
// `RES_BENCH_OUTPUT`, for `res-bench` to read once the process exits.
//
// With `RES_BENCH_LIST` set, `run` measures nothing and writes the names of the
// registered benchmarks instead, so that `res-bench` can run each in a process
// of its own.
//
// mitata's own `run` measures each benchmark the same way: one after another,
// in the order they were registered, skipping those the filter leaves out.
// Before that, though, it spends nearly 4 seconds timing empty functions,
// which only its printed output uses (to warn of a benchmark that may have been
// optimized away). Run once per benchmark, that would cost more than the
// measuring.
//
// It also measures each benchmark with what a benchmark's own `run` method
// (`trial.run()`) picks, which nothing outside can change. This measures it
// with mitata's `measure` instead, so that it can change two things:
//
// - How long each benchmark is sampled for: `RES_BENCH_BUDGET_MS`, mitata's
//   `min_cpu_time`, which is otherwise 642 ms. Its times agree closely within
//   one process; it's from one process to the next that they move, so time is
//   better spent on more processes than on longer ones.
// - No heap statistics, which `res-bench` doesn't record. mitata reads them
//   outside the time it measures, but samples 10% longer to make up for them,
//   and calls them on every sample, next to the measured function.
import {writeFileSync} from 'node:fs';

import * as mitata from 'mitata';

export * from 'mitata';

const trials = [];

// The groups being registered, innermost last, and the one each benchmark was
// registered in: what lets a report put `Belt.Map.get n=1000`, registered in
// the group `get n=1000`, in a column for `Belt.Map`.
const openGroups = [];
const groupOf = new Map();

export function group(...args) {
  openGroups.push(typeof args[0] === 'string' ? args[0] : undefined);
  try {
    return mitata.group(...args);
  } finally {
    openGroups.pop();
  }
}

export function bench(...args) {
  const trial = mitata.bench(...args);
  trials.push(trial);
  groupOf.set(
    trial,
    openGroups.findLast((name) => name !== undefined),
  );
  return trial;
}

const write = (value) =>
  writeFileSync(process.env.RES_BENCH_OUTPUT, JSON.stringify(value));

const budgetMs =
  process.env.RES_BENCH_BUDGET_MS === undefined
    ? undefined
    : Number(process.env.RES_BENCH_BUDGET_MS);

/**
 * Measures `trial` as its `run` method would, apart from the sampling budget
 * and heap statistics (see above), and returns what that would.
 */
const measureTrial = async (trial, thrw) => {
  // A benchmark given arguments (`.args`, `.range`) is measured once for each,
  // which none of the workspace's benchmarks need; those are left to mitata.
  if (Object.keys(trial._args).length > 0) {
    return trial.run(thrw);
  }
  let stats;
  let error;
  try {
    stats = await mitata.measure(trial.f, {
      // As `trial.run()` reads its `.gc()` setting.
      gc: !trial._gc ? false : undefined,
      inner_gc: trial._gc === 'inner',
      ...(budgetMs === undefined ? {} : {min_cpu_time: budgetMs * 1e6}),
    });
  } catch (caught) {
    error = caught;
    if (thrw) {
      throw caught;
    }
  }
  return {kind: 'static', runs: [{stats, error, args: {}, name: trial._name}]};
};

export async function run(options = {}) {
  const filter = options.filter ?? /.*/;
  if (process.env.RES_BENCH_LIST !== undefined) {
    write({names: trials.map((trial) => trial._name)});
    return {layout: [], context: {}, benchmarks: []};
  }
  const ran = [];
  for (const trial of trials) {
    if (filter.test(trial._name)) {
      ran.push([trial, await measureTrial(trial, options.throw ?? false)]);
    }
  }
  const benchmarks = ran.map(([, result]) => result);
  write({
    benchmarks: ran.flatMap(([trial, result]) =>
      result.runs.map(({name, stats, error}) =>
        stats === undefined
          ? {name, error: String(error?.message ?? error)}
          : {
              name,
              group: groupOf.get(trial),
              avg: stats.avg,
              min: stats.min,
              p50: stats.p50,
              p75: stats.p75,
              p99: stats.p99,
              max: stats.max,
              samples: stats.samples.length,
            },
      ),
    ),
  });
  return {layout: [], context: {}, benchmarks};
}
