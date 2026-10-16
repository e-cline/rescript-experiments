# @e-cline/res_signal_maps_benchmarks

Benchmarks for [`@e-cline/res_signal_maps`](..), using
[mitata](https://github.com/evanwashere/mitata) through the bindings in
[`tools/benchmarking`](../../../tools/benchmarking). Not published.

It is a package of its own, rather than part of `res_signal_maps`, so that the benchmarks measure a
production build: `vp build` bundles `src/Main.res`'s compiled output, together with the signal map,
signals, B-tree and ReScript runtime modules it imports, into one Terser-minified `dist/bench.js`,
and that file is what runs.

## Running

From this directory:

```bash
vp run bench
```

This compiles the ReScript, builds the bundle, and runs every benchmark, which takes about 40
seconds. An argument is a regular expression selecting benchmarks by name:

```bash
vp run bench "\.mapValues n="
```

```bash
vp run bench "n=1000$"
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

`src/Main.res` holds all of it. Every benchmark overwrites a value in an `AtomMap` of random `int`
keys, then reads a view derived from it. The views are `mapValues`, `filter`, `map`, `sum`, and a
pipeline of `mapValues`, `filter` and `sum`, each derived from the one before.

Each is measured at 1,000, 10,000 and 100,000 entries, twice:

- **incremental**: over a map keeping its history of diffs, as it does by default, so that the view
  replays the one change.
- **rebuild**: over a map created with `~historyLength=0`, which leaves the view nothing to replay,
  so that it rebuilds from the whole map. This is the cost the incremental update avoids.

One more group reads `mapValues` over 100,000 entries after 1, 8, 64 and 65 writes. A map keeps 64
diffs by default, so after 65 writes its history no longer reaches back to the view's last read and
the view rebuilds.

## Results

From the latest `vp run bench:record`, filled in by `vp run bench:readme`:

<!-- res-bench filter="^(incremental|rebuild)\." -->

|                                   |         incremental |              rebuild |
| --------------------------------- | ------------------: | -------------------: |
| mapValues n=1000                  |   651.17 ns (1.00x) |    22.12 µs (33.97x) |
| mapValues n=10000                 |   818.88 ns (1.00x) |  259.37 µs (316.74x) |
| mapValues n=100000                |     1.04 µs (1.00x) |   4.07 ms (3913.83x) |
| filter n=1000                     | 572.75 ns\* (1.00x) |    16.49 µs (28.80x) |
| filter n=10000                    |   729.46 ns (1.00x) |  188.84 µs (258.88x) |
| filter n=100000                   |   922.34 ns (1.00x) |   2.12 ms (2300.45x) |
| map n=1000                        |     1.09 µs (1.00x) |  167.13 µs (152.97x) |
| map n=10000                       |     1.32 µs (1.00x) |   2.12 ms (1608.59x) |
| map n=100000                      |     1.72 µs (1.00x) | 25.49 ms (14830.00x) |
| sum n=1000                        |   443.99 ns (1.00x) |      1.14 µs (2.57x) |
| sum n=10000                       |   533.80 ns (1.00x) |    14.71 µs (27.55x) |
| sum n=100000                      | 663.40 ns\* (1.00x) |  135.99 µs (204.98x) |
| mapValues > filter > sum n=1000   |     1.00 µs (1.00x) |    26.09 µs (26.03x) |
| mapValues > filter > sum n=10000  |     1.20 µs (1.00x) |  285.78 µs (238.51x) |
| mapValues > filter > sum n=100000 |     1.68 µs (1.00x) |   4.29 ms (2556.66x) |

Median time per call. In brackets, each time's multiple of the fastest in its row. \* marks a
benchmark whose processes landed more than 10% apart. Measured with each benchmark in 5 processes of
its own, with Node v24.22.0 on Apple M2 Pro, 2026-10-15.

<!-- /res-bench -->

Reading `mapValues` over 100,000 entries after more and more writes:

<!-- res-bench filter="after \d+ writes? " -->

|                                    |   median |  fastest |  slowest |
| ---------------------------------- | -------: | -------: | -------: |
| mapValues after 1 write n=100000   |  1.06 µs |  1.04 µs |  1.12 µs |
| mapValues after 8 writes n=100000  |  7.88 µs |  7.80 µs |  7.99 µs |
| mapValues after 64 writes n=100000 | 62.10 µs | 61.56 µs | 62.34 µs |
| mapValues after 65 writes n=100000 |  4.28 ms |  4.02 ms |  4.36 ms |

Median time per call. Measured with each benchmark in 5 processes of its own, with Node v24.22.0 on
Apple M2 Pro, 2026-10-15.

<!-- /res-bench -->

## Reading the results

After mitata's own output, the run ends with a table of every view: the time per call with and
without history, and how many times the faster one's that is.

```
                           incremental             rebuild
mapValues n=1000    624.29 ns    1.00x   21.51 µs   34.45x
mapValues n=10000   781.60 ns    1.00x  226.86 µs  290.25x
mapValues n=100000    1.01 µs    1.00x    3.33 ms 3314.68x

filter n=1000       569.65 ns    1.00x   44.50 µs   78.12x
...
```

A filter that leaves out one side of a view leaves that view out of the table.

- The incremental times include the write: `AtomMap.setValue` updates the B-tree and diffs it
  against the previous one. A map with no history skips that diff, so the rebuild times don't
  include it.
- In the pipeline's rebuild, only the first view rebuilds. Derived views keep a history of their own
  whatever their source does, so the two views after it still update from a diff.
- Compare benchmarks within one run. Absolute times depend on the machine, and on what else it is
  doing.
- Times also depend on which benchmarks ran earlier in the same process, since they share the JIT's
  type feedback: a benchmark run alone through a filter can come out noticeably faster or slower
  than in a full run. Compare like with like. `bench:record` and `bench:compare` run each benchmark
  alone, in processes of its own, so their times are the alone kind.
- The bundle reflects this package's Terser settings (see `vite.config.ts`). `res_signal_maps` ships
  as ReScript source, so a consumer's own bundler configuration decides what they actually run.
