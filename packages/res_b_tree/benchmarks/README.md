# @e-cline/res_b_tree_benchmarks

Benchmarks for [`@e-cline/res_b_tree`](..), using [mitata](https://github.com/evanwashere/mitata)
through the bindings in [`tools/benchmarking`](../../../tools/benchmarking). Not published.

It is a package of its own, rather than part of `res_b_tree`, so that the benchmarks measure a
production build: `vp build` bundles `src/Main.res`'s compiled output, together with the tree and
ReScript runtime modules it imports, into one Terser-minified `dist/bench.js`, and that file is what
runs.

## Running

From this directory:

```bash
vp run bench
```

This compiles the ReScript, builds the bundle, and runs every benchmark: each operation on each of
the package's sorted maps (`BTree`, `AvlTree`, `ChunkTree` at two leaf sizes) and on `Belt.Map`, 212
benchmarks in all, which takes about 3 minutes. An argument is a regular expression selecting
benchmarks by name, which is the implementation, then the operation, then the size:

```bash
vp run bench "^(AvlTree|ChunkTree)\."
```

```bash
vp run bench "\.get n="
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
vp run bench:record "\.get n="
```

To see whether a change made a difference, compare this package's benchmarks at a git ref with the
working tree:

```bash
vp run bench:compare main --filter "^BTree\."
```

Both run each benchmark alone, 5 times, so a filter is what keeps them short: all 212 benchmarks
take about 18 minutes to record, and twice that to compare. Both save what they measured, with an
HTML report of it, under `.bench/` at the repository root. See
[`tools/benchmarking`](../../../tools/benchmarking#measuring-over-several-processes-res-bench) for
their options and how to read their output.

## What is measured

[`src/SortedMapSuite.res`](src/SortedMapSuite.res) measures every implementation the same way, on
trees of 1,000, 10,000 and 100,000 random `int` keys, each built by repeated `set`:

- `get`, `set` (overwriting keys the tree holds, and inserting ones it doesn't), `remove`, `getAt`
  and `indexOf`: 1,000 operations per call, whatever the tree's size, so times at different sizes
  compare directly.
- `set`, building a tree from empty: one insert per key.
- `forEach`, `reduce`, `toArray` and `keysArray` over the whole tree.
- `diff` in four situations: against a tree 10 overwrites away, which shares the rest of its
  structure; against one 30 mixed edits away (overwrites, removals and insertions); against an equal
  tree built again the same way, sharing no node; and against an equal tree built from sorted input,
  which has a different shape too.

`Belt.Map` has no positional access or `diff`, so those aren't measured for it.

[`src/Main.res`](src/Main.res) adds one thing only `BTree` has: inserting then removing 100,000 keys
at a range of `maxNodeSize`s.

## Measuring another tree

Add a module for it to [`src/SortedMaps.res`](src/SortedMaps.res), adapting it to `SortedMapSuite.S`
as the others are, and list it in `all`. Its benchmarks are named after the module's `name`, so a
filter can select it, and the table at the end of a run gets a column for it.

## Results

From the latest `vp run bench:record`, filled in by `vp run bench:readme` (which also fills the
tables in [`../src/avl/README.md`](../src/avl/README.md) and
[`../src/chunk/README.md`](../src/chunk/README.md)):

<!-- res-bench filter=" n=\d+$" -->

|                                                |               BTree |             AvlTree |           ChunkTree |         ChunkTree32 |            Belt.Map |
| ---------------------------------------------- | ------------------: | ------------------: | ------------------: | ------------------: | ------------------: |
| get n=1000                                     |  22.59 µs\* (1.38x) |  19.97 µs\* (1.22x) |  18.94 µs\* (1.16x) |  18.93 µs\* (1.15x) |  16.40 µs\* (1.00x) |
| get n=10000                                    |    27.14 µs (1.00x) |  44.79 µs\* (1.65x) |    48.12 µs (1.77x) |  43.86 µs\* (1.62x) |  40.58 µs\* (1.50x) |
| get n=100000                                   |  50.28 µs\* (1.00x) |    84.99 µs (1.69x) |  83.99 µs\* (1.67x) |  78.69 µs\* (1.57x) |  70.68 µs\* (1.41x) |
| set (build) n=1000                             |   160.33 µs (1.34x) |   119.48 µs (1.00x) | 146.34 µs\* (1.22x) | 143.93 µs\* (1.20x) |   122.56 µs (1.03x) |
| set (build) n=10000                            |     2.39 ms (1.15x) |     2.12 ms (1.03x) |     2.41 ms (1.16x) |     2.30 ms (1.11x) |     2.07 ms (1.00x) |
| set (build) n=100000                           |  35.79 ms\* (1.03x) |  42.47 ms\* (1.23x) |    39.68 ms (1.15x) |    34.64 ms (1.00x) |    39.94 ms (1.15x) |
| set (overwrite) n=1000                         |   110.81 µs (1.15x) |   104.33 µs (1.08x) |   102.81 µs (1.07x) |  96.33 µs\* (1.00x) |    98.41 µs (1.02x) |
| set (overwrite) n=10000                        |   138.55 µs (1.00x) |   163.58 µs (1.18x) |   161.81 µs (1.17x) |   149.53 µs (1.08x) |   161.76 µs (1.17x) |
| set (overwrite) n=100000                       |   186.50 µs (1.00x) |   242.34 µs (1.30x) | 295.33 µs\* (1.58x) |   217.46 µs (1.17x) |   249.86 µs (1.34x) |
| set (insert) n=1000                            |   188.09 µs (1.32x) | 142.91 µs\* (1.00x) | 178.30 µs\* (1.25x) |   176.24 µs (1.23x) |   146.07 µs (1.02x) |
| set (insert) n=10000                           |   199.48 µs (1.13x) |   179.82 µs (1.02x) | 212.13 µs\* (1.21x) |   207.30 µs (1.18x) | 175.83 µs\* (1.00x) |
| set (insert) n=100000                          |   230.26 µs (1.13x) |   217.94 µs (1.07x) |   232.00 µs (1.14x) |   237.54 µs (1.17x) |   203.87 µs (1.00x) |
| remove n=1000                                  |   192.14 µs (1.96x) |  97.84 µs\* (1.00x) |   174.56 µs (1.78x) | 148.72 µs\* (1.52x) | 139.06 µs\* (1.42x) |
| remove n=10000                                 |   230.29 µs (1.27x) |   181.60 µs (1.00x) |   239.02 µs (1.32x) | 226.19 µs\* (1.25x) |   249.70 µs (1.38x) |
| remove n=100000                                | 279.03 µs\* (1.10x) | 253.58 µs\* (1.00x) | 302.04 µs\* (1.19x) |   287.54 µs (1.13x) |   345.15 µs (1.36x) |
| forEach n=1000                                 |     8.29 µs (1.00x) |   8.33 µs\* (1.01x) |     8.29 µs (1.00x) |     8.30 µs (1.00x) |     8.51 µs (1.03x) |
| forEach n=10000                                |    83.39 µs (1.00x) |    87.67 µs (1.06x) |    83.09 µs (1.00x) |    83.24 µs (1.00x) |    92.50 µs (1.11x) |
| forEach n=100000                               |   828.87 µs (1.00x) |   979.82 µs (1.18x) | 835.07 µs\* (1.01x) |   830.90 µs (1.00x) |     1.03 ms (1.24x) |
| reduce n=1000                                  |   677.08 ns (1.00x) |     2.80 µs (4.14x) |   929.52 ns (1.37x) |   690.93 ns (1.02x) |   3.99 µs\* (5.89x) |
| reduce n=10000                                 |     9.02 µs (1.00x) |    65.16 µs (7.23x) |    13.25 µs (1.47x) |     9.37 µs (1.04x) |    75.17 µs (8.33x) |
| reduce n=100000                                |   575.48 µs (1.00x) | 932.61 µs\* (1.62x) | 606.99 µs\* (1.05x) |   583.62 µs (1.01x) |   886.13 µs (1.54x) |
| toArray n=1000                                 |    13.29 µs (3.85x) |     6.13 µs (1.78x) |     3.75 µs (1.09x) |     3.45 µs (1.00x) |   9.15 µs\* (2.65x) |
| toArray n=10000                                | 123.66 µs\* (3.06x) |  80.73 µs\* (2.00x) |    47.81 µs (1.18x) |    40.37 µs (1.00x) |   166.09 µs (4.11x) |
| toArray n=100000                               |   1.69 ms\* (2.35x) |   1.54 ms\* (2.15x) |   824.00 µs (1.15x) |   718.37 µs (1.00x) |     2.30 ms (3.20x) |
| keysArray n=1000                               |     2.73 µs (2.18x) |   3.82 µs\* (3.06x) |     1.51 µs (1.21x) |     1.25 µs (1.00x) |     6.69 µs (5.35x) |
| keysArray n=10000                              |    28.11 µs (2.02x) |  64.56 µs\* (4.64x) |    18.23 µs (1.31x) |    13.91 µs (1.00x) |  140.09 µs (10.07x) |
| keysArray n=100000                             |   504.56 µs (2.17x) |   975.63 µs (4.19x) |   322.99 µs (1.39x) |   232.69 µs (1.00x) |   1.74 ms\* (7.48x) |
| getAt n=1000                                   |  18.53 µs\* (1.60x) |  28.36 µs\* (2.45x) |    13.26 µs (1.14x) |  11.59 µs\* (1.00x) |                     |
| getAt n=10000                                  |  30.38 µs\* (1.34x) |    60.59 µs (2.68x) |  31.33 µs\* (1.39x) |  22.61 µs\* (1.00x) |                     |
| getAt n=100000                                 |  50.00 µs\* (1.00x) |   101.42 µs (2.03x) |  60.68 µs\* (1.21x) |    57.36 µs (1.15x) |                     |
| indexOf n=1000                                 |  20.38 µs\* (1.17x) |  25.69 µs\* (1.47x) |  20.39 µs\* (1.17x) |  17.46 µs\* (1.00x) |                     |
| indexOf n=10000                                |    26.59 µs (1.00x) |    55.05 µs (2.07x) |  40.59 µs\* (1.53x) |    34.94 µs (1.31x) |                     |
| indexOf n=100000                               |    48.64 µs (1.00x) |    92.59 µs (1.90x) |  80.55 µs\* (1.66x) |    66.03 µs (1.36x) |                     |
| diff (10 overwrites) n=1000                    |   473.17 ns (1.24x) |   416.49 ns (1.09x) |   381.83 ns (1.00x) |   431.85 ns (1.13x) |                     |
| diff (10 overwrites) n=10000                   |   843.16 ns (1.21x) |   728.45 ns (1.04x) |   726.68 ns (1.04x) |   697.79 ns (1.00x) |                     |
| diff (10 overwrites) n=100000                  |     1.28 µs (1.41x) |   997.06 ns (1.10x) |   904.59 ns (1.00x) |     1.04 µs (1.15x) |                     |
| diff (30 mixed edits) n=1000                   |     1.39 µs (1.10x) |     1.67 µs (1.33x) |     1.26 µs (1.00x) |     1.63 µs (1.29x) |                     |
| diff (30 mixed edits) n=10000                  |     2.58 µs (1.82x) |     2.00 µs (1.41x) |     1.41 µs (1.00x) |     2.04 µs (1.44x) |                     |
| diff (30 mixed edits) n=100000                 |     3.18 µs (1.59x) |   2.80 µs\* (1.40x) |     2.01 µs (1.00x) |     2.22 µs (1.11x) |                     |
| diff (equal, rebuilt the same way) n=1000      |     4.00 µs (1.44x) |     7.19 µs (2.60x) |     3.48 µs (1.26x) |     2.77 µs (1.00x) |                     |
| diff (equal, rebuilt the same way) n=10000     |    42.39 µs (1.31x) |   113.39 µs (3.50x) |    43.63 µs (1.35x) |    32.41 µs (1.00x) |                     |
| diff (equal, rebuilt the same way) n=100000    |   425.33 µs (1.22x) |   1.42 ms\* (4.06x) |   522.93 µs (1.50x) |   348.76 µs (1.00x) |                     |
| diff (equal, built from sorted input) n=1000   |     4.19 µs (1.63x) |   26.44 µs (10.24x) |     3.16 µs (1.22x) |     2.58 µs (1.00x) |                     |
| diff (equal, built from sorted input) n=10000  |    43.20 µs (1.47x) |   290.85 µs (9.89x) |    41.24 µs (1.40x) |    29.42 µs (1.00x) |                     |
| diff (equal, built from sorted input) n=100000 |   460.38 µs (1.21x) |     3.21 ms (8.45x) |   526.92 µs (1.39x) |   380.33 µs (1.00x) |                     |

Median time per call. In brackets, each time's multiple of the fastest in its row. \* marks a
benchmark whose processes landed more than 10% apart. Measured with each benchmark in 5 processes of
its own, with Node v24.22.0 on Apple M2 Pro, 2026-10-16.

<!-- /res-bench -->

Inserting then removing 100,000 keys, at each `maxNodeSize`:

<!-- res-bench filter="maxNodeSize" -->

|                                     |      median |   fastest |   slowest |
| ----------------------------------- | ----------: | --------: | --------: |
| BTree insert+remove maxNodeSize=4   | 177.34 ms\* | 176.61 ms | 198.93 ms |
| BTree insert+remove maxNodeSize=16  |  87.34 ms\* |  85.94 ms |  95.02 ms |
| BTree insert+remove maxNodeSize=32  |    76.33 ms |  74.67 ms |  80.50 ms |
| BTree insert+remove maxNodeSize=64  |    72.99 ms |  71.04 ms |  78.06 ms |
| BTree insert+remove maxNodeSize=256 |    93.11 ms |  91.84 ms |  98.22 ms |

Median time per call. \* marks a benchmark whose processes landed more than 10% apart. Measured with
each benchmark in 5 processes of its own, with Node v24.22.0 on Apple M2 Pro, 2026-10-16.

<!-- /res-bench -->

## Reading the results

After mitata's own output, the run ends with a table of every operation measured on at least two
implementations: each one's average time per call, and how many times the fastest's that is.

```
                                           BTree             AvlTree           ChunkTree         ChunkTree32           Belt.Map
get n=10000                    27.86 µs    1.00x   44.04 µs    1.58x   41.63 µs    1.49x   34.78 µs    1.25x  41.71 µs    1.50x

getAt n=10000                  28.08 µs    1.00x   57.26 µs    2.04x   38.56 µs    1.37x   33.36 µs    1.19x

diff (10 overwrites) n=10000  838.54 ns    1.17x  718.56 ns    1.00x  718.55 ns    1.00x  799.10 ns    1.11x
```

- Compare benchmarks within one run. Absolute times depend on the machine, and on what else it is
  doing.
- Times also depend on which benchmarks ran earlier in the same process, since they share the JIT's
  type feedback: a benchmark run alone through a filter can come out noticeably faster or slower
  than in a full run. Compare like with like. `bench:record` and `bench:compare` run each benchmark
  alone, in processes of its own, so their times are the alone kind.
- That goes double for comparing implementations in one run. Every implementation is measured by the
  same code in `SortedMapSuite.res`, so in one process that code sees several kinds of tree, and V8
  optimizes it less well for each than if it saw one: which implementation runs first has moved some
  of these results by 10-20%. Run alone, each implementation is measured as if it were the only one,
  so judge one tree against another with `bench:record`.
- The bundle reflects this package's Terser settings (see `vite.config.ts`). `res_b_tree` ships as
  ReScript source, so a consumer's own bundler configuration decides what they actually run.
