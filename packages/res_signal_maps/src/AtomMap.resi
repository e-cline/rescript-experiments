/***
An `Atom`-backed sorted map, loosely modeled on Jane Street's `Incr_map`. Wraps a `BTree.t` in an
`Atom`, exposing the same `get`/`set`/`update` shape as a plain `Atom`, plus every `ComputedMap`
derived-map operation (`mapValues`, `filterMap`, `filter`, `map`, `fold`, `count`, `sum`). Each of
those is a thin wrapper around the identical operation on a `ComputedMap` view of this map's own
signal, so the incremental-update algorithms are written exactly once.

The underlying signal is configured to diff consecutive tree snapshots via `BTree.diff` (see
`MapDiff.ofTrees`), so a derived operation like `mapValues` can update incrementally instead of
recomputing from scratch on every change.

`t` is opaque: nothing outside this module needs the underlying `Atom.t`/`Belt.Id.comparable`
representation, only the functions below.

Every derived-map operation below takes optional `~debugName` (defaults to
`<this map's name>.<operation>`) and `~historyLength` (defaults to `MapDiff.defaultHistoryLength`)
arguments, exactly as in `ComputedMap`; see there for how each operation behaves.
*/

/**
An atom holding a sorted map from `'k` to `'v`, whose keys are ordered by the comparator identified
by `'id`.
*/
type t<'k, 'v, 'id>

/**
Creates an `AtomMap` holding the initial tree.

- `name`: a human-readable identifier for the underlying signal, used for debugging and as the
  default prefix of derived maps' names.
- `historyLength`: how many diffs to retain for downstream incremental updates (defaults to
  `MapDiff.defaultHistoryLength`). Pass `0` to opt out of diffing entirely, which forces every
  derived map to rebuild from scratch on every change.
*/
let make: (
  ~name: string=?,
  ~historyLength: int=?,
  ~id: Belt.Id.comparable<'k, 'id>,
  ResBTree.BTree.t<'k, 'v, 'id>,
) => t<'k, 'v, 'id>

/**
Creates an `AtomMap` seeded with the given entries (or empty, for `[]`) from a `Belt.Id.comparable`
-- shorthand for `make(~id, BTree.fromArray(~id, entries))`, for the common case where there's no
existing tree to hand it. `maxNodeSize` is as in `BTree.make`; the other arguments are as in `make`.
*/
let fromArray: (
  ~name: string=?,
  ~historyLength: int=?,
  ~maxNodeSize: int=?,
  ~id: Belt.Id.comparable<'k, 'id>,
  array<('k, 'v)>,
) => t<'k, 'v, 'id>

/** A read-only `Signal.t` view of this map's underlying tree. */
let signal: t<'k, 'v, 'id> => ResSignals.Signal.t<ResBTree.BTree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>

/**
A read-only `ComputedMap` view of this map -- what every derived-map method below is implemented in
terms of.
*/
let asComputedMap: t<'k, 'v, 'id> => ComputedMap.t<'k, 'v, 'id>

/**
The current tree, capturing this map's underlying signal as a dependency if called from within a
`Computed`/effect.
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
Sets the tree to the given one, and returns the resulting tree. A no-op if it's unchanged (by
`===`). See `Atom.set`.
*/
let set: (t<'k, 'v, 'id>, ResBTree.BTree.t<'k, 'v, 'id>) => ResBTree.BTree.t<'k, 'v, 'id>

/**
Updates the tree using the given function, e.g. `AtomMap.update(m, t => BTree.set(t, k, v))`, and
returns the resulting tree. A no-op if the function returns the very same tree. See `Atom.update`.
*/
let update: (
  t<'k, 'v, 'id>,
  ResBTree.BTree.t<'k, 'v, 'id> => ResBTree.BTree.t<'k, 'v, 'id>,
) => ResBTree.BTree.t<'k, 'v, 'id>

/**
Sets a single key-value pair, and returns the resulting tree. A thin wrapper over `update` and
`BTree.set`. Since `BTree.set` always builds a new tree, setting a key to the value it already has
still counts as a change (with an empty diff), not a no-op.
*/
let setValue: (t<'k, 'v, 'id>, 'k, 'v) => ResBTree.BTree.t<'k, 'v, 'id>

/**
Removes a single key, and returns the resulting tree. A no-op if `key` isn't present. A thin wrapper
over `update` and `BTree.remove`.
*/
let remove: (t<'k, 'v, 'id>, 'k) => ResBTree.BTree.t<'k, 'v, 'id>

/** See `ComputedMap.mapValues`. */
let mapValues: (
  t<'k, 'v, 'id>,
  ~debugName: string=?,
  ~historyLength: int=?,
  ('k, 'v) => 'r,
) => ComputedMap.t<'k, 'r, 'id>

/** See `ComputedMap.filterMap`. */
let filterMap: (
  t<'k, 'v, 'id>,
  ~debugName: string=?,
  ~historyLength: int=?,
  ('k, 'v) => option<'r>,
) => ComputedMap.t<'k, 'r, 'id>

/** See `ComputedMap.filter`. */
let filter: (
  t<'k, 'v, 'id>,
  ~debugName: string=?,
  ~historyLength: int=?,
  ('k, 'v) => bool,
) => ComputedMap.t<'k, 'v, 'id>

/** See `ComputedMap.map`. */
let map: (
  t<'k, 'v, 'id>,
  ~id: Belt.Id.comparable<'k2, 'id2>,
  ~debugName: string=?,
  ~historyLength: int=?,
  ('k, 'v) => ('k2, 'v2),
) => ComputedMap.t<'k2, 'v2, 'id2>

/** See `ComputedMap.fold`. */
let fold: (
  t<'k, 'v, 'id>,
  ~debugName: string=?,
  Fold.spec<'k, 'v, 'acc>,
) => ResSignals.Signal.t<'acc, unit>

/** See `ComputedMap.count`. */
let count: (t<'k, 'v, 'id>, ~debugName: string=?) => ResSignals.Signal.t<int, unit>

/** See `ComputedMap.sum`. */
let sum: (
  t<'k, 'v, 'id>,
  ~debugName: string=?,
  ('k, 'v) => float,
) => ResSignals.Signal.t<float, unit>
