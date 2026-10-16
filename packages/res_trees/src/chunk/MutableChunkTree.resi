/***
A mutable chunked tree: `set`/`remove` change the tree in place, unlike `ChunkTree`, which returns
a new tree from every edit. As `MutableBTree` is to `BTree`, it's a thin wrapper around
`ChunkTree` -- each edit just stores the persistent operation's result back into a single
mutable cell.

The payoff is the same too: `snapshot` is `O(1)` and always safe to hold onto, so diffing
"this tree's contents right now" against "what it looked like earlier" is just `ChunkTree.diff`
on two snapshots.

Its interface is `SortedMap.Mutable` (with `snapshot` returning a `ChunkTree.t`), where each
operation is documented, plus the constructors below. `t` is opaque, and keys are identified via
`Belt.Id.comparable`, exactly as in `ChunkTree`. `checkInvariants` validates the current contents
via `ChunkTree.checkInvariants`.
*/

include SortedMap.Mutable with type persistent<'k, 'v, 'id> := ChunkTree.t<'k, 'v, 'id>

/** An empty tree, ordered by the comparator in `id`. */
let make: (~id: Belt.Id.comparable<'k, 'id>) => t<'k, 'v, 'id>

/** Builds a mutable tree from `entries`; later duplicate keys overwrite earlier ones. */
let fromArray: (~id: Belt.Id.comparable<'k, 'id>, array<('k, 'v)>) => t<'k, 'v, 'id>
