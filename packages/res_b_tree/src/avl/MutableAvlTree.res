// See `MutableAvlTree.resi` for what this module promises. Every function here
// only ever calls `AvlTree.xxx` -- it never reaches into `internal/` itself --
// and `set`/`remove` are the only places the single mutable `tree` cell is
// written.

type t<'k, 'v, 'id> = {mutable tree: AvlTree.t<'k, 'v, 'id>}

let make = (~id: Belt.Id.comparable<'k, 'id>): t<'k, 'v, 'id> => {tree: AvlTree.make(~id)}

let fromArray = (~id: Belt.Id.comparable<'k, 'id>, entries: array<('k, 'v)>): t<'k, 'v, 'id> => {
  tree: AvlTree.fromArray(~id, entries),
}

let get = (self: t<'k, 'v, 'id>, key: 'k): option<'v> => AvlTree.get(self.tree, key)
let has = (self: t<'k, 'v, 'id>, key: 'k): bool => AvlTree.has(self.tree, key)
let size = (self: t<'k, 'v, 'id>): int => AvlTree.size(self.tree)
let isEmpty = (self: t<'k, 'v, 'id>): bool => AvlTree.isEmpty(self.tree)
let minKey = (self: t<'k, 'v, 'id>): option<'k> => AvlTree.minKey(self.tree)
let maxKey = (self: t<'k, 'v, 'id>): option<'k> => AvlTree.maxKey(self.tree)
let getAt = (self: t<'k, 'v, 'id>, index: int): option<('k, 'v)> => AvlTree.getAt(self.tree, index)
let indexOf = (self: t<'k, 'v, 'id>, key: 'k): option<int> => AvlTree.indexOf(self.tree, key)
let toArray = (self: t<'k, 'v, 'id>): array<('k, 'v)> => AvlTree.toArray(self.tree)
let keysArray = (self: t<'k, 'v, 'id>): array<'k> => AvlTree.keysArray(self.tree)
let valuesArray = (self: t<'k, 'v, 'id>): array<'v> => AvlTree.valuesArray(self.tree)
let forEach = (self: t<'k, 'v, 'id>, callback: ('k, 'v) => unit): unit =>
  AvlTree.forEach(self.tree, callback)
let reduce = (self: t<'k, 'v, 'id>, initial: 'acc, callback: ('acc, 'k, 'v) => 'acc): 'acc =>
  AvlTree.reduce(self.tree, initial, callback)

let set = (self: t<'k, 'v, 'id>, key: 'k, value: 'v): unit => {
  self.tree = AvlTree.set(self.tree, key, value)
}

let remove = (self: t<'k, 'v, 'id>, key: 'k): unit => {
  self.tree = AvlTree.remove(self.tree, key)
}

let snapshot = (self: t<'k, 'v, 'id>): AvlTree.t<'k, 'v, 'id> => self.tree

let checkInvariants = (self: t<'k, 'v, 'id>): unit => AvlTree.checkInvariants(self.tree)
