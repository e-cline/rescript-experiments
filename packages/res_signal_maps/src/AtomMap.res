// See `AtomMap.resi` for what this module does; this file is the implementation.
//
// Depends on `@e-cline/res_signals` (`Atom`/`Signal`) and `@e-cline/res_b_tree`
// (`BTree`) -- two other ReScript packages -- directly through ReScript's own
// module system: each namespaces its modules (`ResSignals`/`ResBTree`, per
// their own `rescript.json`'s `"namespace"`), so `Atom`/`Signal`/`BTree` aren't
// visible to another package unqualified -- opened here (and in every other
// file in this package that needs them) rather than qualifying every call.
open ResSignals
open ResBTree

type t<'k, 'v, 'id> = {
  atom: Atom.t<BTree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
  id: Belt.Id.comparable<'k, 'id>,
}

let make = (
  ~name: string="",
  ~historyLength: int=MapDiff.defaultHistoryLength,
  ~id: Belt.Id.comparable<'k, 'id>,
  initialValue: BTree.t<'k, 'v, 'id>,
): t<'k, 'v, 'id> => {
  atom: Atom.makeIncremental(
    ~name,
    ~historyLength,
    ~computeDiff=(prev, curr, _, _) => Some(MapDiff.ofTrees(prev, curr)),
    initialValue,
  ),
  id,
}

let fromArray = (
  ~name: string="",
  ~historyLength: int=MapDiff.defaultHistoryLength,
  ~maxNodeSize: option<int>=?,
  ~id: Belt.Id.comparable<'k, 'id>,
  entries: array<('k, 'v)>,
): t<'k, 'v, 'id> => make(~name, ~historyLength, ~id, BTree.fromArray(~id, ~maxNodeSize?, entries))

let signal = (self: t<'k, 'v, 'id>): Signal.t<BTree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>> =>
  Atom.toSignal(self.atom)

let asComputedMap = (self: t<'k, 'v, 'id>): ComputedMap.t<'k, 'v, 'id> =>
  ComputedMap.fromSignal(signal(self), self.id)

let get = (self: t<'k, 'v, 'id>): BTree.t<'k, 'v, 'id> => Atom.get(self.atom)

let getValue = (self: t<'k, 'v, 'id>, key: 'k): option<'v> => BTree.get(Atom.get(self.atom), key)
let has = (self: t<'k, 'v, 'id>, key: 'k): bool => BTree.has(Atom.get(self.atom), key)
let size = (self: t<'k, 'v, 'id>): int => BTree.size(Atom.get(self.atom))
let isEmpty = (self: t<'k, 'v, 'id>): bool => BTree.isEmpty(Atom.get(self.atom))
let toArray = (self: t<'k, 'v, 'id>): array<('k, 'v)> => BTree.toArray(Atom.get(self.atom))

let set = (self: t<'k, 'v, 'id>, value: BTree.t<'k, 'v, 'id>): BTree.t<'k, 'v, 'id> => {
  Atom.set(self.atom, value)
  Atom.peek(self.atom)
}

let update = (self: t<'k, 'v, 'id>, updater: BTree.t<'k, 'v, 'id> => BTree.t<'k, 'v, 'id>): BTree.t<
  'k,
  'v,
  'id,
> => {
  Atom.update(self.atom, updater)
  Atom.peek(self.atom)
}

let setValue = (self: t<'k, 'v, 'id>, key: 'k, value: 'v): BTree.t<'k, 'v, 'id> =>
  update(self, tree => BTree.set(tree, key, value))

let remove = (self: t<'k, 'v, 'id>, key: 'k): BTree.t<'k, 'v, 'id> =>
  update(self, tree => BTree.remove(tree, key))

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
