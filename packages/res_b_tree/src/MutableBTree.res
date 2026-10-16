// See `MutableBTree.resi` for what this module promises. Every function here
// (including `make`/`fromArray`) only ever calls `BTree.xxx` -- it never reaches
// into `internal/` itself -- and `set`/`remove` are the only places the single
// mutable `tree` cell is written.

type t<'k, 'v, 'id> = {mutable tree: BTree.t<'k, 'v, 'id>}

let make = (~id: Belt.Id.comparable<'k, 'id>, ~maxNodeSize: option<int>=?): t<'k, 'v, 'id> => {
  tree: BTree.make(~id, ~maxNodeSize?),
}

let fromArray = (
  ~id: Belt.Id.comparable<'k, 'id>,
  ~maxNodeSize: option<int>=?,
  entries: array<('k, 'v)>,
): t<'k, 'v, 'id> => {
  tree: BTree.fromArray(~id, ~maxNodeSize?, entries),
}

let get = (self: t<'k, 'v, 'id>, key: 'k): option<'v> => BTree.get(self.tree, key)
let has = (self: t<'k, 'v, 'id>, key: 'k): bool => BTree.has(self.tree, key)
let size = (self: t<'k, 'v, 'id>): int => BTree.size(self.tree)
let isEmpty = (self: t<'k, 'v, 'id>): bool => BTree.isEmpty(self.tree)
let maxNodeSize = (self: t<'k, 'v, 'id>): int => BTree.maxNodeSize(self.tree)
let minKey = (self: t<'k, 'v, 'id>): option<'k> => BTree.minKey(self.tree)
let maxKey = (self: t<'k, 'v, 'id>): option<'k> => BTree.maxKey(self.tree)
let getAt = (self: t<'k, 'v, 'id>, index: int): option<('k, 'v)> => BTree.getAt(self.tree, index)
let indexOf = (self: t<'k, 'v, 'id>, key: 'k): option<int> => BTree.indexOf(self.tree, key)
let toArray = (self: t<'k, 'v, 'id>): array<('k, 'v)> => BTree.toArray(self.tree)
let keysArray = (self: t<'k, 'v, 'id>): array<'k> => BTree.keysArray(self.tree)
let valuesArray = (self: t<'k, 'v, 'id>): array<'v> => BTree.valuesArray(self.tree)
let forEach = (self: t<'k, 'v, 'id>, callback: ('k, 'v) => unit): unit =>
  BTree.forEach(self.tree, callback)
let reduce = (self: t<'k, 'v, 'id>, initial: 'acc, callback: ('acc, 'k, 'v) => 'acc): 'acc =>
  BTree.reduce(self.tree, initial, callback)

let set = (self: t<'k, 'v, 'id>, key: 'k, value: 'v): unit => {
  self.tree = BTree.set(self.tree, key, value)
}

let remove = (self: t<'k, 'v, 'id>, key: 'k): unit => {
  self.tree = BTree.remove(self.tree, key)
}

let snapshot = (self: t<'k, 'v, 'id>): BTree.t<'k, 'v, 'id> => self.tree

let checkInvariants = (self: t<'k, 'v, 'id>): unit => BTree.checkInvariants(self.tree)
