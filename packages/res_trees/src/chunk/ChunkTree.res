// See `ChunkTree.resi` for what this module promises. Everything is in `internal/`: `ChunkMap`
// has the operations at any leaf size, `ChunkNode` the node and `ChunkDiff` the diff. `Make`
// only fixes the leaf size and gives them `AvlTree`'s interface.

module type S = {
  type t<'k, 'v, 'id>

  let make: (~id: Belt.Id.comparable<'k, 'id>) => t<'k, 'v, 'id>

  let fromArray: (~id: Belt.Id.comparable<'k, 'id>, array<('k, 'v)>) => t<'k, 'v, 'id>

  let get: (t<'k, 'v, 'id>, 'k) => option<'v>

  let has: (t<'k, 'v, 'id>, 'k) => bool

  let size: t<'k, 'v, 'id> => int

  let isEmpty: t<'k, 'v, 'id> => bool

  let minKey: t<'k, 'v, 'id> => option<'k>

  let maxKey: t<'k, 'v, 'id> => option<'k>

  let getAt: (t<'k, 'v, 'id>, int) => option<('k, 'v)>

  let indexOf: (t<'k, 'v, 'id>, 'k) => option<int>

  let set: (t<'k, 'v, 'id>, 'k, 'v) => t<'k, 'v, 'id>

  let remove: (t<'k, 'v, 'id>, 'k) => t<'k, 'v, 'id>

  let toArray: t<'k, 'v, 'id> => array<('k, 'v)>

  let keysArray: t<'k, 'v, 'id> => array<'k>

  let valuesArray: t<'k, 'v, 'id> => array<'v>

  let forEach: (t<'k, 'v, 'id>, ('k, 'v) => unit) => unit

  let reduce: (t<'k, 'v, 'id>, 'acc, ('acc, 'k, 'v) => 'acc) => 'acc

  let diff: (
    t<'k, 'v, 'id>,
    t<'k, 'v, 'id>,
    ~valueEqual: ('v, 'v) => bool=?,
    ~onlyLeft: ('k, 'v) => unit=?,
    ~onlyRight: ('k, 'v) => unit=?,
    ~different: ('k, 'v, 'v) => unit=?,
  ) => unit

  let sharedSubtreeCount: (t<'k, 'v, 'id>, t<'k, 'v, 'id>) => int

  let checkInvariants: t<'k, 'v, 'id> => unit
}

module type Config = {
  let maxLeafSize: int
}

module Make = (Config: Config): S => {
  let maxLeafSize = Config.maxLeafSize
  if maxLeafSize < 2 {
    JsError.throwWithMessage("ChunkTree: maxLeafSize must be at least 2")
  }

  type t<'k, 'v, 'id> = ChunkMap.tree<'k, 'v, 'id>

  let make = ChunkMap.make
  let fromArray = (~id, entries) => ChunkMap.fromArray(~id, entries, ~maxLeafSize)
  let get = (tree: t<'k, 'v, 'id>, key) => ChunkMap.get(tree.root, key, ~compare=tree.compare)
  let has = (tree: t<'k, 'v, 'id>, key) => ChunkMap.has(tree.root, key, ~compare=tree.compare)
  let size = (tree: t<'k, 'v, 'id>) => ChunkMap.size(tree.root)
  let isEmpty = (tree: t<'k, 'v, 'id>) => tree.root === None
  let minKey = (tree: t<'k, 'v, 'id>) => ChunkMap.minKey(tree.root)
  let maxKey = (tree: t<'k, 'v, 'id>) => ChunkMap.maxKey(tree.root)
  let getAt = (tree: t<'k, 'v, 'id>, index) => ChunkMap.getAt(tree.root, index)
  let indexOf = (tree: t<'k, 'v, 'id>, key) =>
    ChunkMap.indexOf(tree.root, key, ~compare=tree.compare)
  let set = (tree, key, value) => ChunkMap.set(tree, key, value, ~maxLeafSize)
  let remove = (tree, key) => ChunkMap.remove(tree, key, ~maxLeafSize)
  let toArray = (tree: t<'k, 'v, 'id>) => ChunkMap.toArray(tree.root)
  let keysArray = (tree: t<'k, 'v, 'id>) => ChunkMap.keysArray(tree.root)
  let valuesArray = (tree: t<'k, 'v, 'id>) => ChunkMap.valuesArray(tree.root)
  let forEach = (tree: t<'k, 'v, 'id>, callback) => ChunkMap.forEach(tree.root, callback)
  let reduce = (tree: t<'k, 'v, 'id>, initial, callback) =>
    ChunkMap.reduce(tree.root, initial, callback)
  let diff = (
    left: t<'k, 'v, 'id>,
    right: t<'k, 'v, 'id>,
    ~valueEqual=?,
    ~onlyLeft=?,
    ~onlyRight=?,
    ~different=?,
  ) =>
    ChunkMap.diff(
      left.root,
      right.root,
      ~compare=left.compare,
      ~valueEqual?,
      ~onlyLeft?,
      ~onlyRight?,
      ~different?,
    )
  let sharedSubtreeCount = (left: t<'k, 'v, 'id>, right: t<'k, 'v, 'id>) =>
    ChunkMap.sharedSubtreeCount(left.root, right.root, ~compare=left.compare)
  let checkInvariants = tree => ChunkMap.checkInvariants(tree, ~maxLeafSize)
}

// 16 measured the best balance of reads against writes: see the README.
include Make({
  let maxLeafSize = 16
})
