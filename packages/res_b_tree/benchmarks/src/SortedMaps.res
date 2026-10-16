/***
Every sorted map `SortedMapSuite` measures, adapted to its `S`. To measure another, add a module
here and list it in `all`; its benchmarks are then named after its `name`, so a filter can select
it (`vp run bench "^ChunkTree\."`).
*/

module BTree: SortedMapSuite.S = {
  type t<'k, 'v, 'id> = ResBTree.BTree.t<'k, 'v, 'id>
  let name = "BTree"
  // At its default node size.
  let make = (~id) => ResBTree.BTree.make(~id)
  let fromArray = (~id, entries) => ResBTree.BTree.fromArray(~id, entries)
  let get = ResBTree.BTree.get
  let set = ResBTree.BTree.set
  let remove = ResBTree.BTree.remove
  let forEach = ResBTree.BTree.forEach
  let reduce = ResBTree.BTree.reduce
  let toArray = ResBTree.BTree.toArray
  let keysArray = ResBTree.BTree.keysArray
  let getAt = Some(ResBTree.BTree.getAt)
  let indexOf = Some(ResBTree.BTree.indexOf)
  let diff = Some((left, right, ~different) => ResBTree.BTree.diff(left, right, ~different))
}

module AvlTree: SortedMapSuite.S = {
  type t<'k, 'v, 'id> = ResBTree.AvlTree.t<'k, 'v, 'id>
  let name = "AvlTree"
  let make = ResBTree.AvlTree.make
  let fromArray = ResBTree.AvlTree.fromArray
  let get = ResBTree.AvlTree.get
  let set = ResBTree.AvlTree.set
  let remove = ResBTree.AvlTree.remove
  let forEach = ResBTree.AvlTree.forEach
  let reduce = ResBTree.AvlTree.reduce
  let toArray = ResBTree.AvlTree.toArray
  let keysArray = ResBTree.AvlTree.keysArray
  let getAt = Some(ResBTree.AvlTree.getAt)
  let indexOf = Some(ResBTree.AvlTree.indexOf)
  let diff = Some((left, right, ~different) => ResBTree.AvlTree.diff(left, right, ~different))
}

/** `ChunkTree` and its variants, all of which share its interface. */
module Chunked = (
  Tree: ResBTree.ChunkTree.S,
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

/** With its default leaves of up to 16 entries. */
module ChunkTree = Chunked(
  ResBTree.ChunkTree,
  {
    let name = "ChunkTree"
  },
)

/** With leaves of up to 32 entries. */
module ChunkTree32 = Chunked(
  ResBTree.ChunkTree.Make({
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
