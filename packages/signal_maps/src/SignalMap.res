/***
`AtomMap` and `ComputedMap` for any persistent sorted map. `Make(Trees.ChunkTree)` gives an
`AtomMap` and a `ComputedMap` holding `ChunkTree.t`s, exactly as the package's own `AtomMap` and
`ComputedMap` hold `Trees.BTree.t`s; `Make` takes any `Trees.SortedMap.S`, so `AvlTree`,
`ChunkTree.Make(...)` and any other tree with that interface work too.

```rescript
module ChunkMaps = SignalMap.Make(Trees.ChunkTree)

let prices = ChunkMaps.AtomMap.fromArray(~id=module(IntCmp), [(1, 10.0), (2, 20.0)])
let withTax = prices->ChunkMaps.AtomMap.mapValues((_key, price) => price *. 1.08)
```

The module types here, `ComputedMap` and `AtomMap`, are the interface every such pair has, and
where each operation is documented. Each holds the tree type it was made with as `tree`.

`MakeComputedMap` and `MakeAtomMap` are what `Make` is built from, for a tree whose derived maps
should be built like their source (see `MapTree`): the package's own `AtomMap`/`ComputedMap` use
them with `MapTree.BTree`, so a derived map keeps its source's node size.
*/

open Signals

/**
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

`t` is opaque: nothing outside needs the underlying `Signal.t`/`Belt.Id.comparable`
representation, only the functions below.
*/
module type ComputedMap = {
  /** The persistent sorted map the map holds. */
  type tree<'k, 'v, 'id>

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
    Signal.t<tree<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
    Belt.Id.comparable<'k, 'id>,
  ) => t<'k, 'v, 'id>

  /** The underlying signal's name (for debugging). */
  let name: t<'k, 'v, 'id> => string

  /**
  The current tree, recomputing (or reusing a cached value) as needed, and capturing this map's
  underlying signal as a dependency if called from within a `Computed`/effect.
  */
  let get: t<'k, 'v, 'id> => tree<'k, 'v, 'id>

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
  nothing map-shaped about the result. See `Fold.spec` for how the accumulator is updated. (Takes
  only `debugName`: a scalar accumulator has no diff for a history buffer to hold.)
  */
  let fold: (t<'k, 'v, 'id>, ~debugName: string=?, Fold.spec<'k, 'v, 'acc>) => Signal.t<'acc, unit>

  /** The number of entries in this map, incrementally maintained. A thin wrapper over `fold`. */
  let count: (t<'k, 'v, 'id>, ~debugName: string=?) => Signal.t<int, unit>

  /**
  The sum of `f(key, value)` over every entry, incrementally maintained. A thin wrapper over
  `fold`; it resets to `0.0` whenever the map is empty, which guards against floating-point drift
  accumulating across many add/remove cycles.
  */
  let sum: (t<'k, 'v, 'id>, ~debugName: string=?, ('k, 'v) => float) => Signal.t<float, unit>
}

/**
An `Atom`-backed sorted map, loosely modeled on Jane Street's `Incr_map`. Wraps a tree in an
`Atom`, exposing the same `get`/`set`/`update` shape as a plain `Atom`, plus every `ComputedMap`
derived-map operation (`mapValues`, `filterMap`, `filter`, `map`, `fold`, `count`, `sum`). Each of
those is a thin wrapper around the identical operation on a `ComputedMap` view of this map's own
signal, so the incremental-update algorithms are written exactly once.

The underlying signal is configured to diff consecutive tree snapshots via the tree's `diff` (see
`MapDiff`), so a derived operation like `mapValues` can update incrementally instead of
recomputing from scratch on every change.

`t` is opaque: nothing outside needs the underlying `Atom.t`/`Belt.Id.comparable` representation,
only the functions below.

Every derived-map operation below takes optional `~debugName` (defaults to
`<this map's name>.<operation>`) and `~historyLength` (defaults to `MapDiff.defaultHistoryLength`)
arguments, exactly as in `ComputedMap`; see there for how each operation behaves.
*/
module type AtomMap = {
  /** The persistent sorted map the map holds. */
  type tree<'k, 'v, 'id>

  /** The `ComputedMap` this map's derived maps are. */
  type computedMap<'k, 'v, 'id>

  /**
  An atom holding a sorted map from `'k` to `'v`, whose keys are ordered by the comparator
  identified by `'id`.
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
    tree<'k, 'v, 'id>,
  ) => t<'k, 'v, 'id>

  /**
  Creates an `AtomMap` seeded with the given entries (or empty, for `[]`) -- shorthand for `make`
  with the tree's `fromArray(~id, entries)`, for the common case where there's no existing tree to
  hand it. The other arguments are as in `make`.
  */
  let fromArray: (
    ~name: string=?,
    ~historyLength: int=?,
    ~id: Belt.Id.comparable<'k, 'id>,
    array<('k, 'v)>,
  ) => t<'k, 'v, 'id>

  /** A read-only `Signal.t` view of this map's underlying tree. */
  let signal: t<'k, 'v, 'id> => Signal.t<tree<'k, 'v, 'id>, MapDiff.t<'k, 'v>>

  /**
  A read-only `ComputedMap` view of this map -- what every derived-map method below is implemented
  in terms of.
  */
  let asComputedMap: t<'k, 'v, 'id> => computedMap<'k, 'v, 'id>

  /**
  The current tree, capturing this map's underlying signal as a dependency if called from within a
  `Computed`/effect.
  */
  let get: t<'k, 'v, 'id> => tree<'k, 'v, 'id>

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
  let set: (t<'k, 'v, 'id>, tree<'k, 'v, 'id>) => tree<'k, 'v, 'id>

  /**
  Updates the tree using the given function, e.g.
  `AtomMap.update(m, tree => Trees.BTree.set(tree, k, v))` (with the tree module this map holds),
  and returns the resulting tree. A no-op if the function returns the very same tree. See
  `Atom.update`.
  */
  let update: (t<'k, 'v, 'id>, tree<'k, 'v, 'id> => tree<'k, 'v, 'id>) => tree<'k, 'v, 'id>

  /**
  Sets a single key-value pair, and returns the resulting tree. A thin wrapper over `update` and
  the tree's `set`, which returns the very same tree when `key` already holds exactly `value`
  (`===`), so that is a no-op.
  */
  let setValue: (t<'k, 'v, 'id>, 'k, 'v) => tree<'k, 'v, 'id>

  /**
  Removes a single key, and returns the resulting tree. A no-op if `key` isn't present. A thin
  wrapper over `update` and the tree's `remove`.
  */
  let remove: (t<'k, 'v, 'id>, 'k) => tree<'k, 'v, 'id>

  /** See `ComputedMap.mapValues`. */
  let mapValues: (
    t<'k, 'v, 'id>,
    ~debugName: string=?,
    ~historyLength: int=?,
    ('k, 'v) => 'r,
  ) => computedMap<'k, 'r, 'id>

  /** See `ComputedMap.filterMap`. */
  let filterMap: (
    t<'k, 'v, 'id>,
    ~debugName: string=?,
    ~historyLength: int=?,
    ('k, 'v) => option<'r>,
  ) => computedMap<'k, 'r, 'id>

  /** See `ComputedMap.filter`. */
  let filter: (
    t<'k, 'v, 'id>,
    ~debugName: string=?,
    ~historyLength: int=?,
    ('k, 'v) => bool,
  ) => computedMap<'k, 'v, 'id>

  /** See `ComputedMap.map`. */
  let map: (
    t<'k, 'v, 'id>,
    ~id: Belt.Id.comparable<'k2, 'id2>,
    ~debugName: string=?,
    ~historyLength: int=?,
    ('k, 'v) => ('k2, 'v2),
  ) => computedMap<'k2, 'v2, 'id2>

  /** See `ComputedMap.fold`. */
  let fold: (t<'k, 'v, 'id>, ~debugName: string=?, Fold.spec<'k, 'v, 'acc>) => Signal.t<'acc, unit>

  /** See `ComputedMap.count`. */
  let count: (t<'k, 'v, 'id>, ~debugName: string=?) => Signal.t<int, unit>

  /** See `ComputedMap.sum`. */
  let sum: (t<'k, 'v, 'id>, ~debugName: string=?, ('k, 'v) => float) => Signal.t<float, unit>
}

/** What `Make` gives: a `ComputedMap` and an `AtomMap` over the same tree. */
module type Maps = {
  /** The persistent sorted map both maps hold. */
  type tree<'k, 'v, 'id>
  module ComputedMap: ComputedMap with type tree<'k, 'v, 'id> = tree<'k, 'v, 'id>
  module AtomMap: AtomMap
    with type tree<'k, 'v, 'id> = tree<'k, 'v, 'id>
    and type computedMap<'k, 'v, 'id> = ComputedMap.t<'k, 'v, 'id>
}

/** The `ComputedMap` holding `Tree.t`s. */
module MakeComputedMap = (Tree: MapTree.S): (
  ComputedMap with type tree<'k, 'v, 'id> = Tree.t<'k, 'v, 'id>
) => {
  module MapValues = MapValues.Make(Tree)
  module FilterMap = FilterMap.Make(Tree)
  module Rekey = Rekey.Make(Tree)
  module Fold = Fold.Make(Tree)

  type tree<'k, 'v, 'id> = Tree.t<'k, 'v, 'id>

  type t<'k, 'v, 'id> = {
    signal: Signal.t<Tree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
    id: Belt.Id.comparable<'k, 'id>,
  }

  let fromSignal = (
    signal: Signal.t<Tree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
    id: Belt.Id.comparable<'k, 'id>,
  ): t<'k, 'v, 'id> => {
    signal,
    id,
  }

  let name = (self: t<'k, 'v, 'id>): string => Signal.name(self.signal)

  let get = (self: t<'k, 'v, 'id>): Tree.t<'k, 'v, 'id> => Signal.get(self.signal)

  let getValue = (self: t<'k, 'v, 'id>, key: 'k): option<'v> =>
    Tree.get(Signal.get(self.signal), key)
  let has = (self: t<'k, 'v, 'id>, key: 'k): bool => Tree.has(Signal.get(self.signal), key)
  let size = (self: t<'k, 'v, 'id>): int => Tree.size(Signal.get(self.signal))
  let isEmpty = (self: t<'k, 'v, 'id>): bool => Tree.isEmpty(Signal.get(self.signal))
  let toArray = (self: t<'k, 'v, 'id>): array<('k, 'v)> => Tree.toArray(Signal.get(self.signal))

  /**
  Resolves the optional `~debugName`/`~historyLength` arguments every derived-map operation takes:
  the name defaults to `<this map's name>.<operation>`, and the history length to
  `MapDiff.defaultHistoryLength`.
  */
  let derivedOptions = (
    self: t<'k, 'v, 'id>,
    operation: string,
    debugName: option<string>,
    historyLength: option<int>,
  ): (string, int) => (
    switch debugName {
    | Some(name) => name
    | None => `${Signal.name(self.signal)}.${operation}`
    },
    switch historyLength {
    | Some(n) => n
    | None => MapDiff.defaultHistoryLength
    },
  )

  let mapValues = (
    self: t<'k, 'v, 'id>,
    ~debugName: option<string>=?,
    ~historyLength: option<int>=?,
    mapFn: ('k, 'v) => 'r,
  ): t<'k, 'r, 'id> => {
    let (resolvedName, resolvedHistoryLength) = derivedOptions(
      self,
      "mapValues",
      debugName,
      historyLength,
    )
    fromSignal(
      MapValues.build(
        ~name=resolvedName,
        ~historyLength=resolvedHistoryLength,
        ~id=self.id,
        self.signal,
        mapFn,
      ),
      self.id,
    )
  }

  let filterMap = (
    self: t<'k, 'v, 'id>,
    ~debugName: option<string>=?,
    ~historyLength: option<int>=?,
    filterMapFn: ('k, 'v) => option<'r>,
  ): t<'k, 'r, 'id> => {
    let (name, historyLength) = derivedOptions(self, "filterMap", debugName, historyLength)
    fromSignal(
      FilterMap.build(~name, ~historyLength, ~id=self.id, self.signal, filterMapFn),
      self.id,
    )
  }

  let filter = (
    self: t<'k, 'v, 'id>,
    ~debugName: option<string>=?,
    ~historyLength: option<int>=?,
    predicate: ('k, 'v) => bool,
  ): t<'k, 'v, 'id> =>
    filterMap(self, ~debugName?, ~historyLength?, (key, value) =>
      predicate(key, value) ? Some(value) : None
    )

  let map = (
    self: t<'k, 'v, 'id>,
    ~id: Belt.Id.comparable<'k2, 'id2>,
    ~debugName: option<string>=?,
    ~historyLength: option<int>=?,
    mapFn: ('k, 'v) => ('k2, 'v2),
  ): t<'k2, 'v2, 'id2> => {
    let (name, historyLength) = derivedOptions(self, "map", debugName, historyLength)
    fromSignal(Rekey.build(~name, ~historyLength, ~id, self.signal, mapFn), id)
  }

  let fold = (
    self: t<'k, 'v, 'id>,
    ~debugName: option<string>=?,
    spec: Fold.spec<'k, 'v, 'acc>,
  ): Signal.t<'acc, unit> => {
    let name = switch debugName {
    | Some(name) => name
    | None => `${Signal.name(self.signal)}.fold`
    }
    Fold.build(~name, self.signal, spec)
  }

  let count = (self: t<'k, 'v, 'id>, ~debugName: option<string>=?): Signal.t<int, unit> =>
    fold(
      self,
      ~debugName?,
      {
        init: 0,
        add: (_key, _value, acc) => acc + 1,
        remove: (_key, _value, acc) => acc - 1,
        update: Some((_key, _oldValue, _newValue, acc) => acc),
        revertToInitWhenEmpty: true,
      },
    )

  let sum = (self: t<'k, 'v, 'id>, ~debugName: option<string>=?, f: ('k, 'v) => float): Signal.t<
    float,
    unit,
  > =>
    fold(
      self,
      ~debugName?,
      {
        init: 0.0,
        add: (key, value, acc) => acc +. f(key, value),
        remove: (key, value, acc) => acc -. f(key, value),
        update: None,
        revertToInitWhenEmpty: true,
      },
    )
}

/** The `AtomMap` holding `Tree.t`s, whose derived maps are `ComputedMap`s. */
module MakeAtomMap = (
  Tree: MapTree.S,
  ComputedMap: ComputedMap with type tree<'k, 'v, 'id> = Tree.t<'k, 'v, 'id>,
): (
  AtomMap
    with type tree<'k, 'v, 'id> = Tree.t<'k, 'v, 'id>
    and type computedMap<'k, 'v, 'id> = ComputedMap.t<'k, 'v, 'id>
) => {
  module Diff = MapDiff.Make(Tree)

  type tree<'k, 'v, 'id> = Tree.t<'k, 'v, 'id>
  type computedMap<'k, 'v, 'id> = ComputedMap.t<'k, 'v, 'id>

  type t<'k, 'v, 'id> = {
    atom: Atom.t<Tree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
    id: Belt.Id.comparable<'k, 'id>,
  }

  let make = (
    ~name: string="",
    ~historyLength: int=MapDiff.defaultHistoryLength,
    ~id: Belt.Id.comparable<'k, 'id>,
    initialValue: Tree.t<'k, 'v, 'id>,
  ): t<'k, 'v, 'id> => {
    atom: Atom.makeIncremental(
      ~name,
      ~historyLength,
      ~computeDiff=(prev, curr, _, _) => Some(Diff.ofTrees(prev, curr)),
      initialValue,
    ),
    id,
  }

  let fromArray = (
    ~name: option<string>=?,
    ~historyLength: option<int>=?,
    ~id: Belt.Id.comparable<'k, 'id>,
    entries: array<('k, 'v)>,
  ): t<'k, 'v, 'id> => make(~name?, ~historyLength?, ~id, Tree.fromArray(~id, entries))

  let signal = (self: t<'k, 'v, 'id>): Signal.t<Tree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>> =>
    Atom.toSignal(self.atom)

  let asComputedMap = (self: t<'k, 'v, 'id>): ComputedMap.t<'k, 'v, 'id> =>
    ComputedMap.fromSignal(signal(self), self.id)

  let get = (self: t<'k, 'v, 'id>): Tree.t<'k, 'v, 'id> => Atom.get(self.atom)

  let getValue = (self: t<'k, 'v, 'id>, key: 'k): option<'v> => Tree.get(Atom.get(self.atom), key)
  let has = (self: t<'k, 'v, 'id>, key: 'k): bool => Tree.has(Atom.get(self.atom), key)
  let size = (self: t<'k, 'v, 'id>): int => Tree.size(Atom.get(self.atom))
  let isEmpty = (self: t<'k, 'v, 'id>): bool => Tree.isEmpty(Atom.get(self.atom))
  let toArray = (self: t<'k, 'v, 'id>): array<('k, 'v)> => Tree.toArray(Atom.get(self.atom))

  let set = (self: t<'k, 'v, 'id>, value: Tree.t<'k, 'v, 'id>): Tree.t<'k, 'v, 'id> => {
    Atom.set(self.atom, value)
    Atom.peek(self.atom)
  }

  let update = (self: t<'k, 'v, 'id>, updater: Tree.t<'k, 'v, 'id> => Tree.t<'k, 'v, 'id>): Tree.t<
    'k,
    'v,
    'id,
  > => {
    Atom.update(self.atom, updater)
    Atom.peek(self.atom)
  }

  let setValue = (self: t<'k, 'v, 'id>, key: 'k, value: 'v): Tree.t<'k, 'v, 'id> =>
    update(self, tree => Tree.set(tree, key, value))

  let remove = (self: t<'k, 'v, 'id>, key: 'k): Tree.t<'k, 'v, 'id> =>
    update(self, tree => Tree.remove(tree, key))

  let mapValues = (
    self: t<'k, 'v, 'id>,
    ~debugName: option<string>=?,
    ~historyLength: option<int>=?,
    mapFn: ('k, 'v) => 'r,
  ): ComputedMap.t<'k, 'r, 'id> =>
    ComputedMap.mapValues(asComputedMap(self), ~debugName?, ~historyLength?, mapFn)

  let filterMap = (
    self: t<'k, 'v, 'id>,
    ~debugName: option<string>=?,
    ~historyLength: option<int>=?,
    filterMapFn: ('k, 'v) => option<'r>,
  ): ComputedMap.t<'k, 'r, 'id> =>
    ComputedMap.filterMap(asComputedMap(self), ~debugName?, ~historyLength?, filterMapFn)

  let filter = (
    self: t<'k, 'v, 'id>,
    ~debugName: option<string>=?,
    ~historyLength: option<int>=?,
    predicate: ('k, 'v) => bool,
  ): ComputedMap.t<'k, 'v, 'id> =>
    ComputedMap.filter(asComputedMap(self), ~debugName?, ~historyLength?, predicate)

  let map = (
    self: t<'k, 'v, 'id>,
    ~id: Belt.Id.comparable<'k2, 'id2>,
    ~debugName: option<string>=?,
    ~historyLength: option<int>=?,
    mapFn: ('k, 'v) => ('k2, 'v2),
  ): ComputedMap.t<'k2, 'v2, 'id2> =>
    ComputedMap.map(asComputedMap(self), ~id, ~debugName?, ~historyLength?, mapFn)

  let fold = (
    self: t<'k, 'v, 'id>,
    ~debugName: option<string>=?,
    spec: Fold.spec<'k, 'v, 'acc>,
  ): Signal.t<'acc, unit> => ComputedMap.fold(asComputedMap(self), ~debugName?, spec)

  let count = (self: t<'k, 'v, 'id>, ~debugName: option<string>=?): Signal.t<int, unit> =>
    ComputedMap.count(asComputedMap(self), ~debugName?)

  let sum = (self: t<'k, 'v, 'id>, ~debugName: option<string>=?, f: ('k, 'v) => float): Signal.t<
    float,
    unit,
  > => ComputedMap.sum(asComputedMap(self), ~debugName?, f)
}

/** A `ComputedMap` and an `AtomMap` holding `Tree.t`s. */
module Make = (Tree: Trees.SortedMap.S): (
  Maps with type tree<'k, 'v, 'id> = Tree.t<'k, 'v, 'id>
) => {
  module Adapted = MapTree.OfSortedMap(Tree)
  type tree<'k, 'v, 'id> = Tree.t<'k, 'v, 'id>
  module ComputedMap = MakeComputedMap(Adapted)
  module AtomMap = MakeAtomMap(Adapted, ComputedMap)
}
