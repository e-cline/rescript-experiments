# @e-cline/res_benchmarking

Shared support for the workspace's benchmark packages
([`packages/res_trees/benchmarks`](../../packages/res_trees/benchmarks),
[`packages/res_signals/benchmarks`](../../packages/res_signals/benchmarks) and
[`packages/res_signal_maps/benchmarks`](../../packages/res_signal_maps/benchmarks)). Not published.

- **`Mitata`** -- bindings to [mitata](https://github.com/evanwashere/mitata), covering what the
  benchmarks use rather than the whole library: `bench`, `group`, `summary`, `doNotOptimize` and
  `run`. Also `benchWithSetup`, for a benchmark whose input is built only if it runs.
- **`Comparison`** -- benchmarks several implementations of the same thing, operation by operation,
  and once everything has run prints one table of every operation: the time for each implementation,
  and how many times the fastest's that is.
- **`Runner`** -- `Runner.main`, the call every benchmark program ends with. It runs the registered
  benchmarks, and treats the program's first argument, if any, as a regular expression selecting
  which of them to run by name.
- **`SeededRandom`** -- a seeded PRNG and shuffle, so that every run of a benchmark measures the
  same inputs. It is a copy of the `Random` module in the packages' `tests/TestSupport.res`: those
  are dev-only sources, which a dependent package can't see.
- **`res-bench`** (in `cli/`) -- a command that runs a benchmark package's bundle in several
  processes, saves what they measured, and compares two versions of the code. See below.

## Measuring over several processes: `res-bench`

One run of a benchmark program can't be trusted on its own. Within one process mitata's measurements
agree closely, but the process itself is a lottery: the same bundle, run several times, lands some
benchmarks in different places from one process to the next. `BTree.get n=10000`, for example, comes
out at either about 71 µs or about 91 µs, with nothing in between. Comparing one run from before a
change with one from after can show a 30% "change" in code nobody touched.

`res-bench` runs each measurement in several fresh processes and reports across them. Each benchmark
package has two tasks for it, run from the package's directory.

### `vp run bench:record`

```bash
vp run bench:record
```

```bash
vp run bench:record "n=10000$" --processes 10
```

This builds the bundle and runs each benchmark in 5 processes of its own (`--processes` to change
that), one after another, then prints each benchmark's median time per call. Benchmarks registered
through `Comparison` come out as a table, an implementation to a column, each time followed by how
many times the row's fastest it is:

```
                              BTree             AvlTree
reduce n=1000    661.92 ns    1.00x    2.83 µs    4.27x
reduce n=10000     8.93 µs    1.00x   64.11 µs    7.18x
reduce n=100000  575.08 µs    1.00x  925.82 µs    1.61x
```

The rest are listed with their fastest and slowest process, and the spread between them:

```
                                                             median   fastest   slowest       spread
chain of 1000: write the atom, then read the end (idle)    49.74 µs  49.69 µs  53.79 µs         8.2%
chain of 1000: read the end again, nothing written (idle)   5.53 ns   5.51 ns   7.00 ns  26.9% noisy
```

A benchmark is marked noisy (or `*` in a table) when its processes landed more than 10% apart.

It also writes an HTML report of what it measured; see [Reports](#reports).

### One benchmark per process

By default each process runs a single benchmark, because benchmarks sharing a process move each
other. What one of them does (the garbage it leaves, what the JIT learns from it) changes the time
of the ones after it. Comparing the commits either side of a change that sped up B-tree edits, with
every benchmark in each process, `Belt.Map.set (overwrite) n=100000` came out 8% slower, every
process of the head slower than every process of the base, although no `Belt.Map` code changed. It
runs straight after the B-tree's overwrite benchmark, which the commit made allocate far less.
Measured alone, it was unchanged.

So the times `res-bench` reports are each benchmark's time with nothing run before it, and they can
differ a lot from what the same benchmark shows in a full `vp run bench`. Before the B-tree was
rebuilt, `BTree.reduce n=1000`, for example, took about 8.5 µs alone and about 3.3 µs after the
benchmarks that ran before it in a full run. Neither is the true figure; they're different
situations. What isolation guarantees is that both sides of a comparison are measured in the same
one, whatever else the change touched.

`--shared` runs every benchmark in each process instead, one after another, as `vp run bench` does.
It's quicker when building the benchmarks' inputs is slow, as it is for bundles built from commits
before `Mitata.benchWithSetup` (see "How it works").

### Benchmarks that measure the JIT

Some benchmarks depend less on the code they measure than on what V8 decides to inline, and those
decisions depend on what else has run. Iterating with a callback is the clearest case: every sorted
map's `forEach n=1000` takes about 8.3 µs measured alone, and 2.5-4.5 µs after any `get` benchmark
in the same process. Running other `forEach` benchmarks first doesn't help, and `Belt.Map` behaves
the same as the trees, so the difference isn't in any tree's code.

What differs is whether V8 inlines the callback into the walk that calls it. The same walk and
callback, outside the harness, take 3.2 µs over 1,000 entries, and 6.5 µs with V8's inlining turned
off; turning off escape analysis instead changes nothing, so the cost is the call on every entry.
Whether V8 inlines it depends on its inlining budget. mitata's sampling loop inlines the measured
function when it's the only one the loop has seen, and the tree's walk then competes for the rest of
the budget with mitata's own timer and heap-statistics calls, ranked by how often each was called.
In a trace of the slow case, the walk ranked behind them by less than 0.2% and was left out; after a
`get` benchmark, the same compilation inlined it. Raising V8's budget
(`--max-inlined-bytecode-size-cumulative=4000`) makes `AvlTree.forEach` fast alone every time,
though not `BTree.forEach`, whose walk is recursive and reaches the fast case some other way.

So for benchmarks like these:

- A difference between two implementations can be V8's choice rather than either implementation:
  check whether it survives running the benchmark after another one, with a `--filter` selecting
  both. `forEach` is the one known case here; `toArray n=1000` lands in one of two modes too.
- `bench:compare` still compares like with like, since both sides run in the same situation. A
  change that alters what V8 inlines, though, can move these benchmarks without making the code any
  faster or slower where it's actually used.
- What it says about the code is real but conditional: a callback passed to `forEach` or `reduce`
  costs a call per entry wherever V8 doesn't inline it into the walk, such as from a function that
  is already large, or from one call site passing many different callbacks.

Two ways of hiding this were considered and not taken. Keeping mitata's loop from inlining the
measured function would add a call to every measurement, which would distort benchmarks that take a
few nanoseconds. Raising V8's inlining budget would measure V8 as nobody runs it.

### `vp run bench:compare`

```bash
vp run bench:compare main
```

```bash
vp run bench:compare HEAD~1 HEAD --filter "^BTree\.get"
```

This compares this package's benchmarks at the first git ref (the base) with the second (the head),
or with the working tree if there is no second. The first time it sees a commit, it builds the
package there in a temporary git worktree and keeps the bundle under `.bench/builds/`. It then runs
each benchmark in 5 processes of its own on each side, alternating between the two bundles, so that
anything that drifts over the run, like the machine warming up, falls on both equally.

For each benchmark it prints each side's median time per call, the change between them, and a 99%
interval for that change. Here, comparing a commit with a working tree whose benchmarked code was
identical:

```
                                       base       head  change      99% interval
BTree.get n=10000                  92.86 µs   73.96 µs   -2.3%  [-26.3%, +34.3%]
Belt.Map.get n=10000               52.32 µs   53.18 µs   +1.0%   [-9.8%, +11.1%]
BTree.set (build) n=10000           2.68 ms    2.69 ms   +0.5%    [-0.9%, +2.9%]
Belt.Map.set (overwrite) n=10000  170.48 µs  149.94 µs  -12.0%   [-14.6%, +5.4%]
...

0 faster, 0 slower, 16 with no change the processes can tell apart from noise.
```

A change is reported as faster or slower only when its interval leaves out zero; otherwise the
processes on the two sides overlap too much to tell it from noise. Where an interval is too wide to
answer the question, more processes (`--processes`) narrow it, and a `--filter` keeps that
affordable.

The change is the median of the ratios between every process on one side and every process on the
other (the Hodges-Lehmann estimate), and the interval is the exact one that goes with the
Mann-Whitney test. Neither assumes anything about how the processes' times are spread. Above,
`BTree.get`'s medians are 20% apart only because the base happened to draw more of its slow
processes; the change, -2.3%, isn't moved much by that, and the interval shows how little is known.

The interval is 99% rather than 95% because a comparison tests every benchmark at once: at 95%, one
benchmark in twenty with no real change would be flagged anyway. Comparing a full B-tree bundle with
an identical one flagged 4 of its 53 benchmarks at 95%, and 1 at 99%. It takes at least 5 processes
a side for an interval to reach 99% at all; with 5, a change is flagged only when every process on
one side was faster than every process on the other.

Some benchmarks are bimodal: each process lands in one of two places, with nothing in between.
`BTree.toArray n=1000` comes out at either about 7.9 µs or about 13 µs. With 5 processes a side, one
side can draw mostly one mode and the other mostly the other, and the comparison reports a change
that isn't there. A benchmark `bench:record` marks noisy is worth rerunning with `--processes 20`
and a `--filter` before believing a change in it.

A change in how a benchmark is set up is a change too. Moving the inputs into
`Mitata.benchWithSetup` changed which mode `BTree.toArray n=1000` usually lands in, from the fast
one (18 of 20 processes) to the slow one (14 of 20), although the B-tree's code didn't change, so
compare across that change with care.

The benchmark program must exist, under the same names, at both refs. Benchmarks only one side has
are listed after the table.

### Recordings

Both tasks save what they measured to `.bench/results/` at the repository root (it's gitignored):
every process's measurements, the commit and whether the working tree had changes, the Node version,
CPU, and whether the machine was on battery power. `res-bench` reads them back:

```bash
res-bench show .bench/results/<file>.json
```

```bash
res-bench diff .bench/results/<base>.json .bench/results/<head>.json
```

`diff` compares two recordings made at different times, so unlike `bench:compare` it can't cancel
drift between them. Prefer `bench:compare` for deciding whether a change helped.

### Reports

`bench:record` and `bench:compare` also write an HTML page to `.bench/reports/`, and print its path.
`res-bench report` writes one for any saved recording, or pair of them:

```bash
res-bench report .bench/results/<file>.json
```

```bash
res-bench report .bench/results/<base>.json .bench/results/<head>.json
```

The page is self-contained, so it opens from disk and can be passed around as one file.

- **How time grows with size.** For benchmarks registered through `Comparison` at several sizes
  (`n=1000`, `n=10000`, ...), a small chart per operation of time per call against size, a line per
  implementation, with every process as a faint dot. Hovering a size lists every implementation's
  median and range there.
- **Every benchmark.** The same table `bench:record` prints, where each time also has a strip of its
  processes, from 25% faster than the median to 25% slower. A benchmark that lands in one of two
  places shows two clusters.
- **What changed**, for a pair. Each benchmark's change with its 99% interval, drawn from half the
  base's time to twice it, and marked faster or slower where the interval leaves out zero.

A benchmark's implementation, operation and size come from its name and the mitata group it was
registered in: `Comparison` registers `Belt.Map.get n=1000` in the group `get n=1000`. Recordings
made before `res-bench` recorded groups are shown as a plain list.

### Tables in READMEs

Measurements copied into a README by hand go stale. `res-bench readme` fills them in from a
recording instead: a README marks where a table goes, and which benchmarks it shows, with a pair of
comments,

```markdown
<!-- res-bench filter="^(ChunkTree|AvlTree)\." relative="AvlTree" -->
<!-- /res-bench -->
```

and each benchmark package has a task that fills every such block in the READMEs that use its
benchmarks, from its newest recording:

```bash
vp run bench:record
```

```bash
vp run bench:readme
```

- `filter` selects benchmarks by name, as everywhere else.
- Benchmarks registered through `Comparison` come out an implementation to a column, each median
  followed by its multiple of the row's fastest, or of the implementation `relative` names. Any
  others are listed with their median, fastest and slowest process.
- Under each table is a line saying where, when and how it was measured.
- Filling again replaces what's between the comments, so a block can be refreshed any number of
  times, and the result is already as the formatter would leave it.
- `res-bench readme <file.md>... --from <recording.json>` fills from a particular recording.

Prose that summarizes the numbers ("1.2-2x faster on `get`") is still written by hand: reread it
when the table under it changes.

### How it works

A benchmark bundle leaves `mitata` external, so `res-bench` starts each process with a module hook
(`cli/capture/`) that hands the bundle a version of mitata whose `run` prints nothing and writes its
measurements to a file. The benchmark programs don't need to know about it, which is what lets
`bench:compare` run bundles built from commits older than `res-bench` itself. Both sides of a
comparison also run against this package's copy of mitata, so they're measured by the same harness.

To run each benchmark in processes of its own, `res-bench` first runs the bundle once to list the
benchmarks it registers, measuring nothing, then runs it again for each one with a filter matching
only that one's name. That is affordable because each such process starts quickly:

- The benchmark programs build each benchmark's input in `Mitata.benchWithSetup`, so a process
  builds only what its one benchmark needs. Built up front, every input for every size took about 4
  seconds per process.
- The replacement `run` measures the benchmarks itself, as mitata's own `run` does, one after
  another, but skips what mitata's does first: nearly 4 seconds timing empty functions, which only
  its printed output uses.

Bundles built from commits before `benchWithSetup` still build every input in every process, so
comparing against one of those is much slower unless `--shared` or a narrow `--filter` is given.

`res-bench` is TypeScript run directly by Node, which strips the types; that needs Node 22.18 or
later.

### Checks and tests

Each benchmark package's `test` task runs `res-bench check`, which lists the package's benchmarks
and measures the first in a process of its own, saving nothing: a second or two that tells whether
the bundle still runs under `res-bench`. `--filter` picks another benchmark to measure. So
`vp run test` at the repository root, which CI runs, catches a benchmark program that stops working,
without measuring anything that matters.

`res-bench`'s own tests are `cli/*.test.ts`, run by Node's test runner with `vp run test` here. They
check the statistics against brute force and at the edge of what 99% calls a change, the reading of
implementations and sizes off benchmark names, README filling, the HTML report's escaping, and the
module hook end to end, on a small benchmark program that imports mitata from a directory with no
`node_modules`, as a bundle built from an earlier commit does.

## Writing a benchmark package

A benchmark package depends on this one and on the package it measures, registers its benchmarks at
module top level, and ends by running them with `Runner.main()`:

```rescript
open ResBenchmarking

let comparison = Comparison.make(~implementations=["BTree", "Belt.Map"])

// Each implementation's setup builds its input, then returns what to measure.
comparison->Comparison.bench(
  ~operation="get",
  ~parameter="n=1000",
  [
    (
      "BTree",
      () => {
        let tree = BTree.fromArray(~id, entries)
        {measure: () => Mitata.doNotOptimize(BTree.get(tree, 42))}
      },
    ),
    (
      "Belt.Map",
      () => {
        let map = Belt.Map.fromArray(entries, ~id)
        {measure: () => Mitata.doNotOptimize(Belt.Map.get(map, 42))}
      },
    ),
  ],
)

// Something with no counterpart to compare against is a plain mitata benchmark.
Mitata.benchWithSetup("BTree.getAt n=1000", () => {
  let tree = BTree.fromArray(~id, entries)
  {measure: () => Mitata.doNotOptimize(BTree.getAt(tree, 42))}
})->ignore

comparison->Comparison.print(await Runner.main())
```

Build every input inside a benchmark's setup, not at module top level. Setup runs only if the
benchmark does, and isn't timed, so a filter selecting one benchmark builds only what it needs;
`res-bench` relies on that to run each benchmark in processes of its own. A benchmark that leaves
something running once it's done (an effect subscribed to a signal, say) undoes it in `teardown`:
`{measure, teardown: () => Effect.dispose(effect)}`. A benchmark with no input can still be a plain
`Mitata.bench`.

Pass every benchmark's result to `Mitata.doNotOptimize`. A result nothing reads lets the minifier or
the JIT delete the computation that produced it.

The package needs `mitata` in its own `dependencies` as well as this package: its bundle leaves
`mitata` external, so Node resolves it from the benchmark package's `node_modules` at run time. See
[`packages/res_trees/benchmarks`](../../packages/res_trees/benchmarks) for the build and task
configuration to copy.
