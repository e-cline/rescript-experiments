/***
Bindings to [mitata](https://github.com/evanwashere/mitata), covering what the workspace's
benchmarks use rather than the whole library.

A benchmark file registers its benchmarks at module top level (`bench`, optionally nested in
`group`/`summary`) and then calls `run` once, which measures everything registered and prints
the results.
*/

/** A registered benchmark, as returned by `bench`, for chaining further configuration. */
type benchmark

/**
Registers `callback` as a benchmark called `name`. mitata calls it many times and reports the
time per call, so anything that must not be measured (building the input) belongs outside it.
*/
@module("mitata")
external bench: (string, unit => unit) => benchmark = "bench"

/**
A benchmark's input, once built: `measure` is what mitata times, and `teardown`, if there is one,
runs after it has finished, to undo anything that would otherwise outlive it (an effect left
subscribed, say).
*/
type prepared = {measure: unit => unit, teardown?: unit => unit}

type generator

/**
A generator function, which is what tells mitata to call it once before measuring and take what it
yields as the benchmark. ReScript has no syntax for one.

Between setup and measuring it collects garbage, if `--expose-gc` makes that possible, so that
measuring starts from a settled heap: what setup threw away gone, and what it built moved out of
the young generation, as an input built long before its benchmark runs would have been. Otherwise
the first collections land during measuring, and V8 decides things from them (such as where to
allocate what the measured code allocates) that can move a benchmark's time by half or more.
*/
let generatorOf: (unit => prepared) => generator = %raw(`
  function (setup) {
    return function* () {
      const {measure, teardown} = setup();
      globalThis.gc?.();
      yield measure;
      if (teardown !== undefined) teardown();
    };
  }
`)

@module("mitata")
external benchGenerator: (string, generator) => benchmark = "bench"

/**
Registers a benchmark called `name` whose input `setup` builds. mitata calls `setup` only if the
benchmark runs, just before measuring it, and doesn't count the time it takes, so a filter that
leaves the benchmark out leaves its input unbuilt.

Each benchmark building its own input also keeps benchmarks from sharing one: what one of them does
to an input, or leaves behind in the heap, doesn't carry into the next.
*/
let benchWithSetup = (name: string, setup: unit => prepared): benchmark =>
  benchGenerator(name, generatorOf(setup))

/**
When mitata runs the garbage collector for this benchmark: `#once` (the default) is once, after
warmup; `#inner` is before every sample, which is slower but keeps one sample's garbage from
being collected during the next.
*/
@send
external gc: (benchmark, [#once | #inner]) => benchmark = "gc"

/** Registers every benchmark `callback` registers as one named group in the output. */
@module("mitata")
external group: (string, unit => unit) => unit = "group"

/**
Prints a "x times faster than" comparison of the benchmarks `callback` registers, relative to
the fastest of them.
*/
@module("mitata")
external summary: (unit => unit) => unit = "summary"

/**
Marks `value` as used, in a way neither the minifier nor the JIT can see through. Pass every
benchmark's result to it: a result nothing reads lets either of them delete the computation that
produced it, leaving a benchmark that measures nothing.
*/
@module("mitata")
external doNotOptimize: 'a => unit = "do_not_optimize"

type runOptions = {
  /** Only run benchmarks whose name matches. */
  filter?: RegExp.t,
  /** Whether to color the output. Defaults to whether the terminal supports it. */
  colors?: bool,
}

/** One benchmark's measurements, in nanoseconds per call. */
type stats = {avg: float}

/** One measured run of a benchmark. `stats` is absent if the benchmark threw. */
type run = {name: string, stats?: stats}

/** A benchmark that ran: a single `run`, unless it was given several arguments to run with. */
type trial = {runs: array<run>}

/** What `run` resolves to: the measurements of every benchmark that ran. */
type results = {benchmarks: array<trial>}

/** Runs every registered benchmark, printing results as it goes. */
@module("mitata")
external run: (~options: runOptions=?) => promise<results> = "run"
