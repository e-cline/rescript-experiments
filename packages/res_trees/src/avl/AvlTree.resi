/***
A persistent (immutable) AVL tree: an ordered `('k, 'v)` collection, sorted by key, that
never mutates in place. It offers what `BTree` does -- including `O(log n)` positional access
(`getAt`/`indexOf`) and a `diff` that skips whatever two trees share -- on top of the kind of
tree `Belt.Map` uses, for `Belt.Map`-like speed on point reads and writes. For a mutable,
in-place-feeling API on top of the same tree, see `MutableAvlTree`.

Its interface is `SortedMap.S`, where each operation is documented. `t` is opaque: nothing
outside this file can depend on its representation, only on those functions. Everything under
`internal/` (`AvlNode`, `AvlDiff`) is implementation detail.

## Keys

As in `BTree`, keys are identified via a `Belt.Id.comparable` (built with
`Belt.Id.MakeComparable`), so two trees built from different comparators can't be passed to
`diff`/`sharedSubtreeCount` together: that is a compile error.

## Structural sharing

`set`/`remove` rebuild only the nodes on the path from the root to whatever changed (and the
few a rebalancing rotation touches); every other node is shared with the original tree. `diff`
exploits that to stay cheap: its cost is roughly the number of edits times the tree's height.

## Invariants

`checkInvariants` checks key order, cached heights and sizes, and balance. See `AvlNode.t` for
the exact list.
*/

include SortedMap.S
