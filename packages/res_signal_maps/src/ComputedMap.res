// See `ComputedMap.resi` for what this module does; this file is the implementation.

// See `AtomMap.res`'s own comment on these opens: `Signal`/`Computed` are
// res_signals', `BTree` is res_b_tree's, each reached through its own
// namespace.
open ResSignals
open ResBTree

type t<'k, 'v, 'id> = {
  signal: Signal.t<BTree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
  id: Belt.Id.comparable<'k, 'id>,
}

let fromSignal = (
  signal: Signal.t<BTree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
  id: Belt.Id.comparable<'k, 'id>,
): t<'k, 'v, 'id> => {
  signal,
  id,
}

let name = (self: t<'k, 'v, 'id>): string => Signal.name(self.signal)

let get = (self: t<'k, 'v, 'id>): BTree.t<'k, 'v, 'id> => Signal.get(self.signal)

let getValue = (self: t<'k, 'v, 'id>, key: 'k): option<'v> =>
  BTree.get(Signal.get(self.signal), key)
let has = (self: t<'k, 'v, 'id>, key: 'k): bool => BTree.has(Signal.get(self.signal), key)
let size = (self: t<'k, 'v, 'id>): int => BTree.size(Signal.get(self.signal))
let isEmpty = (self: t<'k, 'v, 'id>): bool => BTree.isEmpty(Signal.get(self.signal))
let toArray = (self: t<'k, 'v, 'id>): array<('k, 'v)> => BTree.toArray(Signal.get(self.signal))

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
  fromSignal(FilterMap.build(~name, ~historyLength, ~id=self.id, self.signal, filterMapFn), self.id)
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
