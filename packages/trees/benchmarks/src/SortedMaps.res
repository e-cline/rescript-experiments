/***
Every sorted map `SortedMapSuite` measures, adapted to its `S`. To measure another, add a module
here and list it in `all`; its benchmarks are then named after its `name`, so a filter can select
it (`vp run bench "^ChunkTree\."`).
*/

module BTree: SortedMapSuite.S = {
  type t<'k, 'v, 'id> = Trees.BTree.t<'k, 'v, 'id>
  let name = "BTree"
  // At its default node size.
  let make = (~id) => Trees.BTree.make(~id)
  let fromArray = (~id, entries) => Trees.BTree.fromArray(~id, entries)
  let get = Trees.BTree.get
  let set = Trees.BTree.set
  let remove = Trees.BTree.remove
  let forEach = Trees.BTree.forEach
  let reduce = Trees.BTree.reduce
  let toArray = Trees.BTree.toArray
  let keysArray = Trees.BTree.keysArray
  let getAt = Some(Trees.BTree.getAt)
  let indexOf = Some(Trees.BTree.indexOf)
  let diff = Some((left, right, ~different) => Trees.BTree.diff(left, right, ~different))
}

/**
Any tree with `SortedMap.S`, the interface `AvlTree` and every `ChunkTree` share. (`BTree` has
`SortedMap.Persistent`, but its constructors also take a node size, so it is adapted by hand above.)
*/
module Adapt = (
  Tree: Trees.SortedMap.S,
  Name: {
    let name: string
  },
): SortedMapSuite.S => {
  type t<'k, 'v, 'id> = Tree.t<'k, 'v, 'id>
  let name = Name.name
  let make = Tree.make
  let fromArray = Tree.fromArray
  let get = Tree.get
  let set = Tree.set
  let remove = Tree.remove
  let forEach = Tree.forEach
  let reduce = Tree.reduce
  let toArray = Tree.toArray
  let keysArray = Tree.keysArray
  let getAt = Some(Tree.getAt)
  let indexOf = Some(Tree.indexOf)
  let diff = Some((left, right, ~different) => Tree.diff(left, right, ~different))
}

module AvlTree = Adapt(
  Trees.AvlTree,
  {
    let name = "AvlTree"
  },
)

/** With its default leaves of up to 16 entries. */
module ChunkTree = Adapt(
  Trees.ChunkTree,
  {
    let name = "ChunkTree"
  },
)

/** With leaves of up to 32 entries. */
module ChunkTree32 = Adapt(
  Trees.ChunkTree.Make({
    let maxLeafSize = 32
  }),
  {
    let name = "ChunkTree32"
  },
)

/** Belt's own sorted map, an AVL tree, as the standard to beat. */
module BeltMap: SortedMapSuite.S = {
  type t<'k, 'v, 'id> = Belt.Map.t<'k, 'v, 'id>
  let name = "Belt.Map"
  let make = Belt.Map.make
  let fromArray = (~id, entries) => Belt.Map.fromArray(entries, ~id)
  let get = Belt.Map.get
  let set = Belt.Map.set
  let remove = Belt.Map.remove
  let forEach = Belt.Map.forEach
  let reduce = Belt.Map.reduce
  let toArray = Belt.Map.toArray
  let keysArray = Belt.Map.keysToArray
  let getAt = None
  let indexOf = None
  let diff = None
}

/** Every implementation, in the order their columns appear in the comparison table. */
let all: array<SortedMapSuite.implementation> = [
  module(BTree),
  module(AvlTree),
  module(ChunkTree),
  module(ChunkTree32),
  module(BeltMap),
]
