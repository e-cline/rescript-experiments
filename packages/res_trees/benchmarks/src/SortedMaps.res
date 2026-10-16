/***
Every sorted map `SortedMapSuite` measures, adapted to its `S`. To measure another, add a module
here and list it in `all`; its benchmarks are then named after its `name`, so a filter can select
it (`vp run bench "^ChunkTree\."`).
*/

module BTree: SortedMapSuite.S = {
  type t<'k, 'v, 'id> = ResTrees.BTree.t<'k, 'v, 'id>
  let name = "BTree"
  // At its default node size.
  let make = (~id) => ResTrees.BTree.make(~id)
  let fromArray = (~id, entries) => ResTrees.BTree.fromArray(~id, entries)
  let get = ResTrees.BTree.get
  let set = ResTrees.BTree.set
  let remove = ResTrees.BTree.remove
  let forEach = ResTrees.BTree.forEach
  let reduce = ResTrees.BTree.reduce
  let toArray = ResTrees.BTree.toArray
  let keysArray = ResTrees.BTree.keysArray
  let getAt = Some(ResTrees.BTree.getAt)
  let indexOf = Some(ResTrees.BTree.indexOf)
  let diff = Some((left, right, ~different) => ResTrees.BTree.diff(left, right, ~different))
}

module AvlTree: SortedMapSuite.S = {
  type t<'k, 'v, 'id> = ResTrees.AvlTree.t<'k, 'v, 'id>
  let name = "AvlTree"
  let make = ResTrees.AvlTree.make
  let fromArray = ResTrees.AvlTree.fromArray
  let get = ResTrees.AvlTree.get
  let set = ResTrees.AvlTree.set
  let remove = ResTrees.AvlTree.remove
  let forEach = ResTrees.AvlTree.forEach
  let reduce = ResTrees.AvlTree.reduce
  let toArray = ResTrees.AvlTree.toArray
  let keysArray = ResTrees.AvlTree.keysArray
  let getAt = Some(ResTrees.AvlTree.getAt)
  let indexOf = Some(ResTrees.AvlTree.indexOf)
  let diff = Some((left, right, ~different) => ResTrees.AvlTree.diff(left, right, ~different))
}

/** `ChunkTree` and its variants, all of which share its interface. */
module Chunked = (
  Tree: ResTrees.ChunkTree.S,
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
  ResTrees.ChunkTree,
  {
    let name = "ChunkTree"
  },
)

/** With leaves of up to 32 entries. */
module ChunkTree32 = Chunked(
  ResTrees.ChunkTree.Make({
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
