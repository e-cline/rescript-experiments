/***
A mutable chunked tree: `set`/`remove` change the tree in place, unlike `ChunkTree`, which returns
a new tree from every edit. As `MutableBTree` is to `BTree`, it's a thin wrapper around
`ChunkTree` -- each edit just stores the persistent operation's result back into a single
mutable cell.

The payoff is the same too: `snapshot` is `O(1)` and always safe to hold onto, so diffing
"this tree's contents right now" against "what it looked like earlier" is just `ChunkTree.diff`
on two snapshots.

`t` is opaque, and keys are identified via `Belt.Id.comparable`, exactly as in `ChunkTree`.
*/

/** A mutable chunked tree from keys `'k` to values `'v`; `'id` identifies the key comparator. */
type t<'k, 'v, 'id>

/** An empty tree, ordered by the comparator in `id`. */
let make: (~id: Belt.Id.comparable<'k, 'id>) => t<'k, 'v, 'id>

/** Builds a mutable tree from `entries`; later duplicate keys overwrite earlier ones. */
let fromArray: (~id: Belt.Id.comparable<'k, 'id>, array<('k, 'v)>) => t<'k, 'v, 'id>

/** The value stored under `key`, if any. */
let get: (t<'k, 'v, 'id>, 'k) => option<'v>

/** Whether `key` is present. */
let has: (t<'k, 'v, 'id>, 'k) => bool

/** The number of entries. */
let size: t<'k, 'v, 'id> => int

/** Whether the tree has no entries. */
let isEmpty: t<'k, 'v, 'id> => bool

/** The smallest key, or `None` if the tree is empty. */
let minKey: t<'k, 'v, 'id> => option<'k>

/** The largest key, or `None` if the tree is empty. */
let maxKey: t<'k, 'v, 'id> => option<'k>

/**
The entry at position `index` in ascending key order (0-based), or `None` if `index` is out of
range.
*/
let getAt: (t<'k, 'v, 'id>, int) => option<('k, 'v)>

/** The position (0-based, ascending key order) of `key`, or `None` if it isn't present. */
let indexOf: (t<'k, 'v, 'id>, 'k) => option<int>

/** All entries, sorted ascending by key. */
let toArray: t<'k, 'v, 'id> => array<('k, 'v)>

/** All keys, in ascending order. */
let keysArray: t<'k, 'v, 'id> => array<'k>

/** All values, in ascending order of their keys. */
let valuesArray: t<'k, 'v, 'id> => array<'v>

/** Calls `callback` for every entry, in ascending key order. */
let forEach: (t<'k, 'v, 'id>, ('k, 'v) => unit) => unit

/** Folds over every entry, in ascending key order. */
let reduce: (t<'k, 'v, 'id>, 'acc, ('acc, 'k, 'v) => 'acc) => 'acc

/** Sets `key` to `value` in place, overwriting any existing value. */
let set: (t<'k, 'v, 'id>, 'k, 'v) => unit

/** Removes `key` in place, if present; a no-op if it isn't. */
let remove: (t<'k, 'v, 'id>, 'k) => unit

/**
A cheap (`O(1)`), always-safe-to-keep immutable snapshot of the tree's current contents.

It stays safe because nothing in this module (or in `ChunkTree`) ever mutates an `ChunkTree.t`'s
nodes in place: only this module's own cell changes, and only to point at a new, independent
`ChunkTree.t`.
*/
let snapshot: t<'k, 'v, 'id> => ChunkTree.t<'k, 'v, 'id>

/** A diagnostic, intended for tests: validates the current contents via `ChunkTree.checkInvariants`. */
let checkInvariants: t<'k, 'v, 'id> => unit
