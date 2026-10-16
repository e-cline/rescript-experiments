/***
A read-only, sorted, signal-backed map derived from an `AtomMap` or another `ComputedMap` -- what
`mapValues`/`filterMap`/`filter`/`map` return. Loosely modeled on Jane Street's `Incr_map`; see
`AtomMap` for the shared design.

Every derived-map operation (`mapValues`, `filterMap`, `filter`, `map`, `fold`, `count`, `sum`)
updates incrementally: it replays the changes its source reports since it was last read (see
`MapDiff`) instead of recomputing from scratch, falling back to a full rebuild only when the
source's history can't cover the gap. Each takes optional arguments:

- `debugName`: names the derived signal, for debugging. Defaults to
  `<source map's name>.<operation>`, e.g. `"prices.mapValues"`.
- `historyLength`: how many diffs the derived map retains for *its own* downstream consumers.
  Defaults to `MapDiff.defaultHistoryLength`.

`t` is opaque: nothing outside this module needs the underlying `Signal.t`/`Belt.Id.comparable`
representation, only the functions below.
*/

/**
A read-only sorted map from `'k` to `'v`, whose keys are ordered by the comparator identified by
`'id`.
*/
type t<'k, 'v, 'id>

/**
Wraps an existing signal (and the comparator its tree uses) as a `ComputedMap` -- the seam
`AtomMap`'s own derived-map methods use, so the incremental-update algorithms only need to be
written once.
*/
let fromSignal: (
  ResSignals.Signal.t<ResBTree.BTree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
  Belt.Id.comparable<'k, 'id>,
) => t<'k, 'v, 'id>

/** The underlying signal's name (for debugging). */
let name: t<'k, 'v, 'id> => string

/**
The current tree, recomputing (or reusing a cached value) as needed, and capturing this map's
underlying signal as a dependency if called from within a `Computed`/effect.
*/
let get: t<'k, 'v, 'id> => ResBTree.BTree.t<'k, 'v, 'id>

/** The value stored under `key` in the current tree, if any. Captures a dependency, like `get`. */
let getValue: (t<'k, 'v, 'id>, 'k) => option<'v>

/** Whether `key` is in the current tree. Captures a dependency, like `get`. */
let has: (t<'k, 'v, 'id>, 'k) => bool

/** The number of entries in the current tree. Captures a dependency, like `get`. */
let size: t<'k, 'v, 'id> => int

/** Whether the current tree is empty. Captures a dependency, like `get`. */
let isEmpty: t<'k, 'v, 'id> => bool

/** The current tree's entries, sorted ascending by key. Captures a dependency, like `get`. */
let toArray: t<'k, 'v, 'id> => array<('k, 'v)>

/**
Returns a new `ComputedMap` with every value replaced by `mapFn(key, value)`. Updates
incrementally -- touching only the keys that changed -- instead of re-running `mapFn` over every
entry on every change.
*/
let mapValues: (
  t<'k, 'v, 'id>,
  ~debugName: string=?,
  ~historyLength: int=?,
  ('k, 'v) => 'r,
) => t<'k, 'r, 'id>

/**
Returns a new `ComputedMap` containing `filterMapFn(key, value)` for every entry for which it
returns `Some`; keys are unchanged.
*/
let filterMap: (
  t<'k, 'v, 'id>,
  ~debugName: string=?,
  ~historyLength: int=?,
  ('k, 'v) => option<'r>,
) => t<'k, 'r, 'id>

/**
Returns a new `ComputedMap` holding every entry for which the predicate returns `true`. A thin
wrapper over `filterMap`.
*/
let filter: (
  t<'k, 'v, 'id>,
  ~debugName: string=?,
  ~historyLength: int=?,
  ('k, 'v) => bool,
) => t<'k, 'v, 'id>

/**
Returns a new `ComputedMap` containing `mapFn(key, value)` for every entry, keyed and ordered by
`id`. Unlike `mapValues`, `map` can change a key's identity, not just its value; `mapFn` must be
injective over this map's keys at all times, or this throws (from whichever read first
observes the collision).
*/
let map: (
  t<'k, 'v, 'id>,
  ~id: Belt.Id.comparable<'k2, 'id2>,
  ~debugName: string=?,
  ~historyLength: int=?,
  ('k, 'v) => ('k2, 'v2),
) => t<'k2, 'v2, 'id2>

/**
Incrementally folds this map's entries into a single accumulator, modeled on Jane Street's
`Incr_map.unordered_fold`. Returns a plain `Signal.t<'acc, unit>`, not a `ComputedMap` -- there's
nothing map-shaped about the result. See `Fold.spec` for how the accumulator is updated. (Takes only
`debugName`: a scalar accumulator has no diff for a history buffer to hold.)
*/
let fold: (
  t<'k, 'v, 'id>,
  ~debugName: string=?,
  Fold.spec<'k, 'v, 'acc>,
) => ResSignals.Signal.t<'acc, unit>

/** The number of entries in this map, incrementally maintained. A thin wrapper over `fold`. */
let count: (t<'k, 'v, 'id>, ~debugName: string=?) => ResSignals.Signal.t<int, unit>

/**
The sum of `f(key, value)` over every entry, incrementally maintained. A thin wrapper over `fold`;
it resets to `0.0` whenever the map is empty, which guards against floating-point drift accumulating
across many add/remove cycles.
*/
let sum: (
  t<'k, 'v, 'id>,
  ~debugName: string=?,
  ('k, 'v) => float,
) => ResSignals.Signal.t<float, unit>
