# @e-cline/signals_benchmarks

Benchmarks for [`@e-cline/signals`](..), using [mitata](https://github.com/evanwashere/mitata)
through the bindings in [`tools/benchmarking`](../../../tools/benchmarking). Not published.

It is a package of its own, rather than part of `signals`, so that the benchmarks measure a
production build: `vp build` bundles `src/Main.res`'s compiled output, together with the signals and
ReScript runtime modules it imports, into one Terser-minified `dist/bench.js`, and that file is what
runs.

## Running

From this directory:

```bash
vp run bench
```

This compiles the ReScript, builds the bundle, and runs every benchmark, which takes about 20
seconds. An argument is a regular expression selecting benchmarks by name:

```bash
vp run bench "\(idle\)$"
```

```bash
vp run bench "16000"
```

To see what bundling and minifying change, run the same benchmarks straight from the compiler's
unbundled output:

```bash
vp run bench:unbundled
```

A single run can land a benchmark tens of percent away from where the next run puts it, so for
numbers to rely on, run the benchmarks in several processes:

```bash
vp run bench:record
```

To see whether a change made a difference, compare this package's benchmarks at a git ref with the
working tree:

```bash
vp run bench:compare main
```

Both take a filter too, and save what they measured, with an HTML report of it, under `.bench/` at
the repository root. See
[`tools/benchmarking`](../../../tools/benchmarking#measuring-over-several-processes-res-bench) for
their options and how to read their output.

## What is measured

`src/Main.res` holds all of it: how the dependency graph's costs scale. The first three groups each
run at 1,000 and at 16,000 nodes, so a cost that grows faster than the graph does stands out:

- One computed reading every atom: writing one atom, then either reading the computed or letting an
  effect on it rerun.
- Many effects on one atom: creating then disposing them all, and one write that reruns them all.
- Many computeds on one atom: creating and reading them all, and one write that recomputes them all
  for an effect.
- A chain of 1,000 computeds, each reading the one before: writing the atom at its start, writing an
  unrelated atom, and reading the end again with nothing written.

"Live" means an effect depends on what is measured, so a write pushes through the graph by itself;
"idle" means nothing does, and the work happens when the benchmark reads.

## Results

From the latest `vp run bench:record`, filled in by `vp run bench:readme`:

<!-- res-bench filter="." -->

|                                                                      |     median |   fastest |   slowest |
| -------------------------------------------------------------------- | ---------: | --------: | --------: |
| write one of 1000 atoms, then read the computed (idle)               |    8.86 µs |   8.69 µs |   8.95 µs |
| write one of 1000 atoms, rerunning an effect on the computed (live)  |    9.03 µs |   8.95 µs |   9.07 µs |
| create 1000 effects, then dispose them all                           |  256.21 µs | 249.63 µs | 267.46 µs |
| one write, rerunning 1000 effects                                    |   50.03 µs |  48.67 µs |  51.00 µs |
| create and read 1000 computeds, then drop them (idle)                |  133.45 µs | 131.13 µs | 139.41 µs |
| one write, recomputing 1000 computeds for an effect (live)           |   82.24 µs |  81.81 µs |  83.58 µs |
| write one of 16000 atoms, then read the computed (idle)              |  162.83 µs | 159.90 µs | 163.14 µs |
| write one of 16000 atoms, rerunning an effect on the computed (live) |  146.24 µs | 145.76 µs | 150.30 µs |
| create 16000 effects, then dispose them all                          |    6.01 ms |   5.90 ms |   6.19 ms |
| one write, rerunning 16000 effects                                   |  817.97 µs | 817.67 µs | 845.92 µs |
| create and read 16000 computeds, then drop them (idle)               |    2.49 ms |   2.45 ms |   2.54 ms |
| one write, recomputing 16000 computeds for an effect (live)          |    1.50 ms |   1.48 ms |   1.57 ms |
| chain of 1000: write the atom, rerunning an effect on the end (live) |   93.58 µs |  92.50 µs |  94.54 µs |
| chain of 1000: write the atom, then read the end (idle)              | 50.52 µs\* |  50.14 µs |  55.26 µs |
| chain of 1000: write an unrelated atom, then read the end (idle)     |   15.71 µs |  14.74 µs |  16.23 µs |
| chain of 1000: read the end again, nothing written (idle)            |    3.99 ns |   3.96 ns |   4.04 ns |

Median time per call. \* marks a benchmark whose processes landed more than 10% apart. Measured with
each benchmark in 5 processes of its own, with Node v24.22.0 on Apple M2 Pro, 2026-10-15.

<!-- /res-bench -->

## Reading the results

- Compare benchmarks within one run. Absolute times depend on the machine, and on what else it is
  doing.
- Times also depend on which benchmarks ran earlier in the same process, since they share the JIT's
  type feedback: a benchmark run alone through a filter can come out noticeably faster or slower
  than in a full run. Compare like with like. `bench:record` and `bench:compare` run each benchmark
  alone, in processes of its own, so their times are the alone kind.
- Each benchmark builds its own graph when it runs, and disposes of the effects on it once measured,
  so a filter selecting one benchmark builds only that one's graph, and no graph outlives its
  benchmark.
- The bundle reflects this package's Terser settings (see `vite.config.ts`). `signals` ships as
  ReScript source, so a consumer's own bundler configuration decides what they actually run.
