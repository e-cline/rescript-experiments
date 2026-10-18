/***
A mutable B-tree: `set`/`remove` change the tree in place, unlike `BTree`, which returns a
new tree from every edit. It's a thin wrapper around `BTree` -- each edit just stores the
persistent operation's result back into a single mutable cell -- so it costs the same
`O(log n)` per edit as a purpose-built in-place tree would, without a second B-tree
implementation to maintain.

The payoff: `snapshot` is `O(1)` and always safe to hold onto (see its own comment), so
diffing "this tree's contents right now" against "what it looked like earlier" is just
`BTree.diff` on two snapshots.

Its interface is `SortedMap.Mutable` (with `snapshot` returning a `BTree.t`), where each
operation is documented, plus the constructors and `maxNodeSize` below. As in `BTree.resi`, `t`
is opaque, for the same reason: nothing outside this module should depend on its being "just" a
mutable cell around a `BTree.t`, only on the functions below. Keys are identified via
`Belt.Id.comparable`, exactly as in `BTree`. `checkInvariants` validates the current contents
via `BTree.checkInvariants`.
*/

include SortedMap.Mutable with type persistent<'k, 'v, 'id> := BTree.t<'k, 'v, 'id>

/** An empty tree, ordered by the comparator in `id`. `maxNodeSize` is as in `BTree.make`. */
let make: (~id: Belt.Id.comparable<'k, 'id>, ~maxNodeSize: int=?) => t<'k, 'v, 'id>

/** Builds a mutable tree from `entries`; later duplicate keys overwrite earlier ones. */
let fromArray: (
  ~id: Belt.Id.comparable<'k, 'id>,
  ~maxNodeSize: int=?,
  array<('k, 'v)>,
) => t<'k, 'v, 'id>

/** The maximum node size the tree is actually using, after `BTree.make`'s clamping. */
let maxNodeSize: t<'k, 'v, 'id> => int
