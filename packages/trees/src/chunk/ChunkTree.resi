/***
A persistent sorted map built on a leaf-chunked AVL tree: a height-balanced binary spine whose
leaves are small sorted arrays. It has `AvlTree`'s interface and keeps its fast point writes and
its cheap `diff`, while iterating and reading by position more like a B-tree. For a mutable,
in-place-feeling API on top of the same tree, see `MutableChunkTree`. See `README.md` in this
directory for how it works and how it measures.

Its interface is `SortedMap.S`, where each operation is documented. `t` is opaque, and keys are
identified via `Belt.Id.comparable` (built with `Belt.Id.MakeComparable`), exactly as in
`AvlTree` and `BTree`.

Leaves hold up to 16 entries. `Make` gives the same tree with another maximum; trees from
different applications of it are different types.

## Diff

A diff costs roughly the number of edits times the tree's height. Leaves that share their `keys`
array, as an overwrite leaves them, are compared by value alone, without calling the comparator;
and values that are `===` are taken as equal without calling `valueEqual`.

## Invariants

`checkInvariants` checks key order, separators, cached heights and sizes, balance and how full
each leaf is. See `ChunkNode` for the exact list.
*/

/** The interface every leaf size shares: `SortedMap.S`, as `AvlTree` has. */
module type S = SortedMap.S

include S

module type Config = {
  /**
  The most entries a leaf may hold. A leaf other than the root holds at least half as many.
  Must be at least 2. Larger leaves read and iterate faster and insert and remove a little slower:
  see the README.
  */
  let maxLeafSize: int
}

/** The tree with leaves of up to `Config.maxLeafSize` entries. */
module Make: (Config: Config) => S
