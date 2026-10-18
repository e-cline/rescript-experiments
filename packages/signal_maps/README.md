# @e-cline/signal_maps

A sorted, signal-backed map -- `AtomMap`/`ComputedMap` -- authored in ReScript, extracted from
[`@e-cline/signals`](../signals) (which this package depends on for `Atom`/`Computed`/ `Signal`) and
built on [`@e-cline/trees`](../trees)'s `BTree.t`, or on any of its other trees through
`SignalMap.Make`. Loosely modeled on Jane Street's `Incr_map`. `AtomMap`'s derived views
(`mapValues`, `filterMap`, `map`, `fold`, ...) update incrementally from a diff instead of
recomputing from scratch on every change.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/signal_maps rescript @rescript/runtime
```

Add `"@e-cline/signal_maps"` to the `dependencies` in your `rescript.json`. The modules are under
the `SignalMaps` namespace (`SignalMaps.AtomMap.make`), and your project's `rescript build` compiles
them along with your own code.

`AtomMap` is built from a `Trees.BTree.t` (or another `trees` tree; see
[Over another tree](#over-another-tree)), and its views are `Signals` signals, so you'll usually
want `@e-cline/trees` and `@e-cline/signals` installed and listed as well.

## `AtomMap` / `ComputedMap`: efficient incremental map updates

`AtomMap` (backed by a signals `Atom`) whose derived views (`ComputedMap`) update incrementally by
replaying a diff against the _previous_ result, instead of recomputing from scratch. Built on
`@e-cline/trees`'s `BTree.t` -- an immutable B-tree with structural-sharing-aware diffing
(`BTree.diff`), which is what makes `AtomMap.set`/`update` cheap to diff against the previous tree
in the first place.

```rescript
module IntCmp = Belt.Id.MakeComparable({
  type t = int
  let cmp = (a, b) => a - b
})

let prices = AtomMap.fromArray(~id=module(IntCmp), [(1, 10.0), (2, 20.0)])
let withTax = prices->AtomMap.mapValues((_key, price) => price *. 1.08)
let total = withTax->ComputedMap.sum((_key, price) => price)

Signal.get(total) // 32.4
AtomMap.setValue(prices, 3, 5.0) // only key 3's mapFn runs; total updates incrementally
```

- **`mapValues`** -- remaps every value; replays the source's diff directly against the previous
  result tree (`internal/MapValues.res`).
- **`filterMap`** / **`filter`** -- keeps entries passing a predicate; same in-place-replay
  strategy, with bookkeeping for entries crossing the filter boundary (`internal/FilterMap.res`).
- **`map`** -- can change a key's identity, not just its value; modeled on `Incr_map.rekey`, using a
  remove-then-deferred-add strategy within each diff batch so a same-batch key swap doesn't trip
  over itself, and a genuine collision throws instead of silently overwriting
  (`internal/Rekey.res` -- see its own comment on what counts as "the same batch").
- **`fold`** / **`count`** / **`sum`** -- an incrementally-maintained accumulator, modeled on
  `Incr_map.unordered_fold` (`internal/Fold.res`).

On the first computation, or whenever a derived map's history can't cover the gap since it last
looked (`Signal.Reset`, from signals), every one of these falls back to a full rebuild from the
source's current tree -- correctness never depends on the diff being available, only performance
does.

**Not included (yet):** `subrange`/`subrangeByIndex` (a reactive key-space or index window),
`groupBy` (bucketing into a map-of-maps), and `minBy`/`maxBy`. None of the incremental-update
machinery they'd need is missing -- they're straightforward extensions of the same `internal/*.res`
pattern -- they just weren't asked for and would each be their own reasonably-sized addition.
`AtomMap`/`ComputedMap` also aren't a `Signal.t` themselves; use `AtomMap.signal`/
`AtomMap.asComputedMap` to get one explicitly where needed.

## Over another tree

`AtomMap` and `ComputedMap` hold a `BTree.t`, the fastest of `trees`' trees to read. For a map that
is written more than read, `AvlTree` inserts and removes fastest, and `ChunkTree` sits between the
two (see [its README](../trees/README.md)). `SignalMap.Make` gives the same `AtomMap` and
`ComputedMap` over any tree with `Trees.SortedMap.S`, the interface those two share:

```rescript
module ChunkMaps = SignalMap.Make(Trees.ChunkTree)

let prices = ChunkMaps.AtomMap.fromArray(~id=module(IntCmp), [(1, 10.0), (2, 20.0)])
let total = prices->ChunkMaps.AtomMap.sum((_key, price) => price)
```

Every operation is documented once, in [`src/SignalMap.res`](src/SignalMap.res): its module types
`SignalMap.AtomMap` and `SignalMap.ComputedMap` are the interface every such pair has, and the
package's own `AtomMap.resi` and `ComputedMap.resi` are an `include` of them (with a `fromArray`
that also takes `BTree`'s node size). Each holds its tree type as `tree`.

A derived map of a `BTree` is built with its source's node size. That's what
[`src/MapTree.res`](src/MapTree.res) is for: `MapTree.S` is `Trees.SortedMap.S` plus constructors
that build a tree like an existing one, and `SignalMap.MakeComputedMap`/`MakeAtomMap` take one, for
a tree with settings of its own to carry over. `SignalMap.Make` wraps a `Trees.SortedMap.S`, which
has none.

## Benchmarks

The benchmarks in [`benchmarks/`](benchmarks) (a separate, unpublished package) measure what a write
costs each derived view, against what it costs when the view has to rebuild from scratch instead:

```bash
pnpm --filter @e-cline/signal_maps_benchmarks exec vp run bench
```

## Design notes

- **No class hierarchy.** ReScript has no inheritance; `AtomMap`/`ComputedMap` share their
  incremental-update algorithms via functors in `internal/` (over the tree, `MapTree.S`) that both
  call, and `SignalMap`'s module types and functors stand in for a base class.
- **No `Belt.Id.comparable` unpacking.** `map`'s collision detection uses the tree's `has` before
  each insert instead of sorting entries with a directly-extracted comparator function (see
  `internal/Rekey.res`), sidestepping the locally-abstract-type dance `Belt.Id`-based comparators
  otherwise need (see the root `RESCRIPT.md`'s gap #11).

## No separate low-level API

Every derived-map algorithm here (`internal/MapValues.res`, `FilterMap.res`, `Rekey.res`,
`Fold.res`) is built entirely on `@e-cline/signals`'s existing _public_ surface --
`Computed.makeIncremental` (which already hands back the previous value and a `getDiffSince`-style
epoch for exactly this kind of incremental rebuild) and `Signal.t` itself. None of it reaches into
signals' own `internal/` (`Node`, `Epoch`, `HistoryBuffer`); there was no need to carve out a
separate `Internal` module on the signals side for this package to depend on.

## A note for anyone extending this package

Cross-package references need the dependency's namespace opened (or qualified) explicitly --
`@e-cline/signals`'s `rescript.json` sets `"namespace": "Signals"` and `@e-cline/trees`'s sets
`"namespace": "Trees"`, so every file here that reaches for `Atom`/`Signal`/`Computed` starts with
`open Signals`, and every one that names a tree qualifies it (`Trees.BTree`, `Trees.SortedMap`; see
`AtomMap.res`'s own comment on this). Omitting one doesn't fail loudly with an "unknown namespace"
error; it fails as a plain "the module or file `Atom`/`BTree` can't be found," which is easy to
mistake for the dependency not being wired up in `rescript.json`/`package.json` at all.
