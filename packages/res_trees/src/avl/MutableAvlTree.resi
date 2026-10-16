/***
A mutable AVL tree: `set`/`remove` change the tree in place, unlike `AvlTree`, which returns
a new tree from every edit. As `MutableBTree` is to `BTree`, it's a thin wrapper around
`AvlTree` -- each edit just stores the persistent operation's result back into a single
mutable cell.

The payoff is the same too: `snapshot` is `O(1)` and always safe to hold onto, so diffing
"this tree's contents right now" against "what it looked like earlier" is just `AvlTree.diff`
on two snapshots.

Its interface is `SortedMap.Mutable` (with `snapshot` returning an `AvlTree.t`), where each
operation is documented, plus the constructors below. `t` is opaque, and keys are identified via
`Belt.Id.comparable`, exactly as in `AvlTree`. `checkInvariants` validates the current contents
via `AvlTree.checkInvariants`.
*/

include SortedMap.Mutable with type persistent<'k, 'v, 'id> := AvlTree.t<'k, 'v, 'id>

/** An empty tree, ordered by the comparator in `id`. */
let make: (~id: Belt.Id.comparable<'k, 'id>) => t<'k, 'v, 'id>

/** Builds a mutable tree from `entries`; later duplicate keys overwrite earlier ones. */
let fromArray: (~id: Belt.Id.comparable<'k, 'id>, array<('k, 'v)>) => t<'k, 'v, 'id>
