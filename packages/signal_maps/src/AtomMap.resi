/***
An `Atom`-backed sorted map holding a `Trees.BTree.t`, loosely modeled on Jane Street's
`Incr_map`, whose derived maps (`mapValues`, `filterMap`, `map`, ...) are `ComputedMap`s and
update incrementally from the tree's `diff`. A derived map's tree has the same node size as its
source's.

Its interface is `SignalMap.AtomMap`, where each operation is documented, with a `fromArray` that
also takes `BTree`'s node size. For the same map over another tree, see `SignalMap.Make`.
*/

include SignalMap.AtomMap
  with type tree<'k, 'v, 'id> = Trees.BTree.t<'k, 'v, 'id>
  and type computedMap<'k, 'v, 'id> = ComputedMap.t<'k, 'v, 'id>

/**
Creates an `AtomMap` seeded with the given entries (or empty, for `[]`) from a `Belt.Id.comparable`
-- shorthand for `make(~id, BTree.fromArray(~id, entries))`, for the common case where there's no
existing tree to hand it. `maxNodeSize` is as in `BTree.make`; the other arguments are as in `make`.
*/
let fromArray: (
  ~name: string=?,
  ~historyLength: int=?,
  ~maxNodeSize: int=?,
  ~id: Belt.Id.comparable<'k, 'id>,
  array<('k, 'v)>,
) => t<'k, 'v, 'id>
