/***
What `AtomMap`/`ComputedMap` need from the persistent sorted map they're built on: `S`. It is
`Trees.SortedMap.S` (which `AvlTree`, `ChunkTree` and any other tree with that interface have)
plus two constructors that build a tree *like* an existing one, so that a derived map is built the
way its source was: a `mapValues` of a `BTree` with nodes of 8 is itself a `BTree` with nodes of 8.

`OfSortedMap` makes an `S` of any `Trees.SortedMap.S`, whose trees have nothing to carry over,
and `BTree` is the one `AtomMap`/`ComputedMap` are built on. `SignalMap.Make` takes a
`Trees.SortedMap.S` and applies `OfSortedMap` itself, so most code never needs this module.
*/

module type S = {
  include Trees.SortedMap.S

  /**
  An empty tree ordered by `id`, built the way `like` was (with its node size, say), whatever
  `like` holds.
  */
  let emptyLike: (t<'k0, 'v0, 'id0>, ~id: Belt.Id.comparable<'k, 'id>) => t<'k, 'v, 'id>

  /**
  `fromArray`, building the tree the way `like` was. `entries` is often already in ascending key
  order (it's read out of a source tree in order), which `fromArray` builds in `O(n)`.
  */
  let fromArrayLike: (
    t<'k0, 'v0, 'id0>,
    ~id: Belt.Id.comparable<'k, 'id>,
    array<('k, 'v)>,
  ) => t<'k, 'v, 'id>
}

/** Any `Trees.SortedMap.S` as an `S`: its trees have no settings to carry over. */
module OfSortedMap = (Tree: Trees.SortedMap.S): (
  S with type t<'k, 'v, 'id> = Tree.t<'k, 'v, 'id>
) => {
  include Tree
  let emptyLike = (_like, ~id) => Tree.make(~id)
  let fromArrayLike = (_like, ~id, entries) => Tree.fromArray(~id, entries)
}

/**
`Trees.BTree` as an `S`: `make` and `fromArray` use the default node size, and `emptyLike` and
`fromArrayLike` the node size of the tree they're given.
*/
module BTree: S with type t<'k, 'v, 'id> = Trees.BTree.t<'k, 'v, 'id> = {
  include Trees.BTree
  let make = (~id) => Trees.BTree.make(~id)
  let fromArray = (~id, entries) => Trees.BTree.fromArray(~id, entries)
  let emptyLike = (like, ~id) => Trees.BTree.make(~id, ~maxNodeSize=Trees.BTree.maxNodeSize(like))
  let fromArrayLike = (like, ~id, entries) =>
    Trees.BTree.fromArray(~id, ~maxNodeSize=Trees.BTree.maxNodeSize(like), entries)
}
