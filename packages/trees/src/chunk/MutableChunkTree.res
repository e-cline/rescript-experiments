// See `MutableChunkTree.resi` for what this module promises. Every function here
// only ever calls `ChunkTree.xxx` -- it never reaches into `internal/` itself --
// and `set`/`remove` are the only places the single mutable `tree` cell is
// written.

type t<'k, 'v, 'id> = {mutable tree: ChunkTree.t<'k, 'v, 'id>}

let make = (~id: Belt.Id.comparable<'k, 'id>): t<'k, 'v, 'id> => {tree: ChunkTree.make(~id)}

let fromArray = (~id: Belt.Id.comparable<'k, 'id>, entries: array<('k, 'v)>): t<'k, 'v, 'id> => {
  tree: ChunkTree.fromArray(~id, entries),
}

let get = (self: t<'k, 'v, 'id>, key: 'k): option<'v> => ChunkTree.get(self.tree, key)
let has = (self: t<'k, 'v, 'id>, key: 'k): bool => ChunkTree.has(self.tree, key)
let size = (self: t<'k, 'v, 'id>): int => ChunkTree.size(self.tree)
let isEmpty = (self: t<'k, 'v, 'id>): bool => ChunkTree.isEmpty(self.tree)
let minKey = (self: t<'k, 'v, 'id>): option<'k> => ChunkTree.minKey(self.tree)
let maxKey = (self: t<'k, 'v, 'id>): option<'k> => ChunkTree.maxKey(self.tree)
let getAt = (self: t<'k, 'v, 'id>, index: int): option<('k, 'v)> =>
  ChunkTree.getAt(self.tree, index)
let indexOf = (self: t<'k, 'v, 'id>, key: 'k): option<int> => ChunkTree.indexOf(self.tree, key)
let toArray = (self: t<'k, 'v, 'id>): array<('k, 'v)> => ChunkTree.toArray(self.tree)
let keysArray = (self: t<'k, 'v, 'id>): array<'k> => ChunkTree.keysArray(self.tree)
let valuesArray = (self: t<'k, 'v, 'id>): array<'v> => ChunkTree.valuesArray(self.tree)
let forEach = (self: t<'k, 'v, 'id>, callback: ('k, 'v) => unit): unit =>
  ChunkTree.forEach(self.tree, callback)
let reduce = (self: t<'k, 'v, 'id>, initial: 'acc, callback: ('acc, 'k, 'v) => 'acc): 'acc =>
  ChunkTree.reduce(self.tree, initial, callback)

let set = (self: t<'k, 'v, 'id>, key: 'k, value: 'v): unit => {
  self.tree = ChunkTree.set(self.tree, key, value)
}

let remove = (self: t<'k, 'v, 'id>, key: 'k): unit => {
  self.tree = ChunkTree.remove(self.tree, key)
}

let snapshot = (self: t<'k, 'v, 'id>): ChunkTree.t<'k, 'v, 'id> => self.tree

let checkInvariants = (self: t<'k, 'v, 'id>): unit => ChunkTree.checkInvariants(self.tree)
