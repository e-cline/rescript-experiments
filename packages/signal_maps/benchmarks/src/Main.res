/***
Benchmarks for `AtomMap`'s derived views. What they promise is that a change to the map costs the
view in proportion to the change, not to the map, so each view is measured twice: over a map
keeping its history of diffs (the default), which the view replays, and over one created with
`~historyLength=0`, which leaves the view nothing to do but rebuild from scratch. Those pairs go
through `Comparison`, which prints a table of all of them once everything has run.

Every benchmark passes what it reads to `Mitata.doNotOptimize`. This file is bundled together with
the code it measures (see ../vite.config.ts), so without that both Terser and the JIT could see
that a result is unused and delete the work that produced it.

Every benchmark builds its own map and view, when it runs (see `Mitata.benchWithSetup`), so a
filter that selects one benchmark builds only what that one needs.

Benchmark names include the operation and the map's size, since the filter argument (see
`Runner.main`) matches on a benchmark's own name, not its group's.
*/

open Benchmarking
module Signal = Signals.Signal
module AtomMap = SignalMaps.AtomMap
module ComputedMap = SignalMaps.ComputedMap
module MapDiff = SignalMaps.MapDiff

module IntCmp = Belt.Id.MakeComparable({
  type t = int
  let cmp = (a: int, b: int) => a - b
})

let id: Belt.Id.comparable<int, IntCmp.identity> = module(IntCmp)

type map = AtomMap.t<int, int, IntCmp.identity>

/** Derives a view of a map, and returns a function that reads it. */
type view = map => unit => unit

let comparison = Comparison.make(~implementations=["incremental", "rebuild"])

/** How many distinct keys a benchmark's writes cycle through. */
let probeCount = 1_000

let mapValues: view = map => {
  let doubled = map->AtomMap.mapValues((_, value) => value * 2)
  () => Mitata.doNotOptimize(ComputedMap.get(doubled))
}

// Half the values written are even, so writes move entries into and out of the view as well as
// changing ones that stay in it.
let filter: view = map => {
  let evens = map->AtomMap.filter((_, value) => mod(value, 2) == 0)
  () => Mitata.doNotOptimize(ComputedMap.get(evens))
}

let map: view = map => {
  let negated = map->AtomMap.map(~id, (key, value) => (-key, value))
  () => Mitata.doNotOptimize(ComputedMap.get(negated))
}

let sum: view = map => {
  let total = map->AtomMap.sum((_, value) => Int.toFloat(value))
  () => Mitata.doNotOptimize(Signal.get(total))
}

/** Three views, each derived from the one before. */
let pipeline: view = map => {
  let total =
    map
    ->AtomMap.mapValues((_, value) => value * 2)
    ->ComputedMap.filter((key, _) => mod(key, 2) == 0)
    ->ComputedMap.sum((_, value) => Int.toFloat(value))
  () => Mitata.doNotOptimize(Signal.get(total))
}

/**
A benchmark of `view` over a map of `n` entries, as `Mitata.benchWithSetup` takes it: each call
overwrites `writes` of the map's values, one write at a time, then reads the view once. The view's
first computation, which is always a full build, happens here rather than in the benchmark.
*/
let writeThenRead = (~historyLength: int, ~writes: int=1, n: int, view: view): Mitata.prepared => {
  let random = SeededRandom.make(42.0)
  let entries = SeededRandom.shuffledRange(random, n)->Array.map(key => (key, key))
  let probes = SeededRandom.shuffledRange(random, n)->Array.slice(~start=0, ~end=probeCount)
  let map = AtomMap.fromArray(~id, ~historyLength, entries)
  let read = view(map)
  read()
  // Counts the writes made so far. It picks the key, and is the value written, so that no write
  // leaves its key's value as it was.
  let written = ref(0)
  {
    measure: () => {
      for _ in 1 to writes {
        written := written.contents + 1
        let key = Array.getUnsafe(probes, mod(written.contents, probeCount))
        AtomMap.setValue(map, key, -written.contents)->ignore
      }
      read()
    },
  }
}

let benchMapOfSize = (n: int) => {
  let parameter = `n=${Int.toString(n)}`

  [
    ("mapValues", mapValues),
    ("filter", filter),
    ("map", map),
    ("sum", sum),
    ("mapValues > filter > sum", pipeline),
  ]->Array.forEach(((operation, view)) =>
    comparison->Comparison.bench(
      ~operation,
      ~parameter,
      [
        ("incremental", () => writeThenRead(~historyLength=MapDiff.defaultHistoryLength, n, view)),
        ("rebuild", () => writeThenRead(~historyLength=0, n, view)),
      ],
    )
  )
}

/**
Reads a view after more and more writes to a map of `n` entries, up to one more than the map keeps
diffs for. Past that the history no longer reaches back to the view's last read, and the view has
to rebuild.
*/
let benchWritesPerRead = (n: int) => {
  let historyLength = MapDiff.defaultHistoryLength

  Mitata.group(`writes per read, n=${Int.toString(n)}`, () =>
    [1, 8, historyLength, historyLength + 1]->Array.forEach(writes =>
      Mitata.benchWithSetup(
        `mapValues after ${Int.toString(writes)} ${writes == 1
            ? "write"
            : "writes"} n=${Int.toString(n)}`,
        () => writeThenRead(~historyLength, ~writes, n, mapValues),
      )->ignore
    )
  )
}

[1_000, 10_000, 100_000]->Array.forEach(benchMapOfSize)
benchWritesPerRead(100_000)

comparison->Comparison.print(await Runner.main())
