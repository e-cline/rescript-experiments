# @e-cline/weft_core_benchmarks

Benchmarks for [`@e-cline/weft_core`](..), using [mitata](https://github.com/evanwashere/mitata)
through the bindings in [`tools/benchmarking`](../../../tools/benchmarking). Not published.

Like the other benchmark packages, it is a package of its own so that the benchmarks measure a
production build: `vp build` bundles `src/Main.res`'s compiled output, with the reconciler and the
ReScript runtime it imports, into one Terser-minified `dist/bench.js`, and that file is what runs.

## Running

From this directory:

```bash
vp run bench
```

An argument is a regular expression selecting benchmarks by name:

```bash
vp run bench "10000 keyed"
```

For numbers to rely on, run each benchmark in several processes of its own, or compare a git ref
with the working tree:

```bash
vp run bench:record
```

```bash
vp run bench:compare main
```

See [`tools/benchmarking`](../../../tools/benchmarking#measuring-over-several-processes-res-bench)
for their options and how to read their output.

## What is measured

A list of rows (`<ul>` of keyed `<li>`s, each rendered by a component), at 1,000 and 10,000 rows,
put through the operations of the well-known JS framework benchmark:

- mounting and then unmounting the list;
- replacing every row's text, and rendering it again with nothing changed;
- one row updating its own state;
- reversing the rows, swapping two of them (the second and the second-to-last), and removing one
  from the middle (then putting it back);
- changing a context value that every (memoized) row reads, with nothing else re-rendering;
- rendering new text for every row in a transition, yielding every 100 units of work.

Everything renders into `src/BenchHost.res`: in-memory nodes whose child lists are doubly linked, so
appending, inserting and removing are constant time, as in the DOM. The times are therefore the
reconciler's, not a host's. Transitions run on `src/BenchScheduler.res`, which ends a slice after
every 100 `shouldYield` checks instead of after 5 ms, so they yield as often on any machine.

Every benchmark alternates between two states (or mounts and unmounts), so each call does the same
work, and checks the result once while setting up: that the list has the right rows, in the right
order, with the right text.

## Results

From the latest `vp run bench:record`, filled in by `vp run bench:readme`:

<!-- res-bench filter="." -->

|                                                             |     median |   fastest |   slowest |
| ----------------------------------------------------------- | ---------: | --------: | --------: |
| mount, then unmount, 1000 rows                              |  264.47 µs | 259.80 µs | 271.53 µs |
| replace the text of all 1000 rows                           |  263.10 µs | 257.77 µs | 264.32 µs |
| render 1000 rows again, nothing changed                     |  211.15 µs | 209.58 µs | 220.01 µs |
| one of 1000 rows updates its own state                      | 48.21 µs\* |  46.37 µs |  51.63 µs |
| reverse 1000 keyed rows                                     |  335.67 µs | 331.28 µs | 337.80 µs |
| swap two of 1000 keyed rows                                 |  338.20 µs | 330.13 µs | 343.48 µs |
| remove, then restore, one of 1000 keyed rows                |  249.40 µs | 245.39 µs | 252.42 µs |
| change a context read by 1000 memoized rows                 |  283.54 µs | 264.34 µs | 283.92 µs |
| render 1000 rows in a transition, yielding every 100 units  |  271.70 µs | 264.94 µs | 273.10 µs |
| mount, then unmount, 10000 rows                             |    3.38 ms |   3.35 ms |   3.45 ms |
| replace the text of all 10000 rows                          |    3.93 ms |   3.80 ms |   3.96 ms |
| render 10000 rows again, nothing changed                    |    2.40 ms |   2.29 ms |   2.44 ms |
| one of 10000 rows updates its own state                     |  463.56 µs | 442.64 µs | 466.96 µs |
| reverse 10000 keyed rows                                    |    5.11 ms |   4.93 ms |   5.14 ms |
| swap two of 10000 keyed rows                                |  4.61 ms\* |   4.27 ms |   4.85 ms |
| remove, then restore, one of 10000 keyed rows               |    2.97 ms |   2.89 ms |   2.98 ms |
| change a context read by 10000 memoized rows                |  3.29 ms\* |   3.05 ms |   3.75 ms |
| render 10000 rows in a transition, yielding every 100 units |  3.89 ms\* |   3.42 ms |   3.93 ms |

Median time per call. \* marks a benchmark whose processes landed more than 10% apart. Measured at
503f393 with uncommitted changes, each benchmark in 5 processes of its own, with Node v24.22.0 on
Apple M2 Pro, 2026-10-17.

<!-- /res-bench -->

## What they showed

The first run of these benchmarks found that reversing 10,000 rows took 231 ms, against 2.9 ms for
1,000: quadratic. The commit phase placed moved children first to last, and each one searched for
the node it goes before by walking past every later sibling that was also moving (React has the same
search, with a TODO about it). Placing a parent's moved children last first means each finds the
sibling after it already in position. Reversing 10,000 rows now takes about 5 ms, and every
operation grows linearly with the list.

"One row updates its own state" is the operation that should cost the least: nothing renders but the
row. It still grows with the list, because reaching the row clones every sibling fiber of the
`<ul>`'s children on the way (bailing out of them without rendering), as React's reconciler does.

## Bundle size

`vp run size` (from here or from the repository root) measures what `weft_core` and `weft_dom` add
to an app's production bundle:

| Bytes                                                                   | minified |   gzip | brotli |
| ----------------------------------------------------------------------- | -------: | -----: | -----: |
| [`size/Counter.res`](size/Counter.res): one `useState` and a `<button>` |   32,432 | 10,359 |  9,416 |
| [`size/FullApi.res`](size/FullApi.res): every hook and component, once  |   36,104 | 11,690 | 10,624 |
| [the todo app](../../../examples/weft_app)                              |   36,377 | 11,811 | 10,743 |

Measured at 246a2a1, 2026-10-18. Each app is bundled on its own by Vite in production mode, into one
ES module, and minified by Terser (top-level mangling, 3 compress passes) until another run stops
shrinking it; then compressed with gzip (level 9) and brotli (quality 11). The script,
[`size/size.ts`](size/size.ts), also fails if a bundle includes development-only code (the key
warnings, behind `Common.Env.isDev`) or a full error message (production builds throw codes): a
production build resolves `@e-cline/js_env` to constants that let the minifier drop them.

The counter already carries most of the code: using the whole API adds about 3.7 KB (1.3 KB
gzipped). (Resolving `Lazy` elements, rejected ones included, is part of the reconciler, so every
app carries it: about 0.9 KB minified, 300 B gzipped.)

### A possible further reduction: short property names

Minifiers rename variables but not properties, so the internal records' field names
(`memoizedProps`, `alternate`, `workInProgressHook` and the rest) appear in full in every production
bundle, and they are about an eighth of the counter's minified size. Giving those fields short
JavaScript names with `@as` (`@as("mp") mutable memoizedProps: unknown`), while keeping the ReScript
names, would make the counter about 4.1 KB smaller minified and 400 B gzipped. It was tried and then
left out, because the short names make fibers and hooks harder to read in a debugger. It would cover
the fields of `Fiber.t`, `FiberRoot.t` and the hook, update, queue, effect, context, error-boundary
and scheduler records, but not public shapes such as props records or `Ref.t`.

## Reading the results

- Compare benchmarks within one run: absolute times depend on the machine, and on what else it is
  doing.
- Times also depend on which benchmarks ran earlier in the same process, since they share the JIT's
  type feedback. `bench:record` and `bench:compare` run each benchmark alone, in processes of its
  own.
