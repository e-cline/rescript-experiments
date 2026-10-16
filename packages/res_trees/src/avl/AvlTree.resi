/***
A persistent (immutable) AVL tree: an ordered `('k, 'v)` collection, sorted by key, that
never mutates in place. It offers what `BTree` does -- including `O(log n)` positional access
(`getAt`/`indexOf`) and a `diff` that skips whatever two trees share -- on top of the kind of
tree `Belt.Map` uses, for `Belt.Map`-like speed on point reads and writes. For a mutable,
in-place-feeling API on top of the same tree, see `MutableAvlTree`.

`t` is opaque: nothing outside this file can depend on its representation, only on the
functions below. Everything under `internal/` (`AvlNode`, `AvlDiff`) is implementation detail.

## Keys

As in `BTree`, keys are identified via a `Belt.Id.comparable` (built with
`Belt.Id.MakeComparable`), so two trees built from different comparators can't be passed to
`diff`/`sharedSubtreeCount` together: that is a compile error.

## Structural sharing

`set`/`remove` rebuild only the nodes on the path from the root to whatever changed (and the
few a rebalancing rotation touches); every other node is shared with the original tree. `diff`
exploits that to stay cheap (see its own comment).
*/

/**
A persistent AVL tree from keys `'k` to values `'v`; `'id` identifies the key comparator (see
the module comment).
*/
type t<'k, 'v, 'id>

/** An empty tree, ordered by the comparator in `id`. */
let make: (~id: Belt.Id.comparable<'k, 'id>) => t<'k, 'v, 'id>

/**
Builds a tree from `entries`; later duplicate keys overwrite earlier ones. `O(n)` if `entries`
is already in strictly ascending key order, `O(n log n)` (repeated `set`) otherwise.
*/
let fromArray: (~id: Belt.Id.comparable<'k, 'id>, array<('k, 'v)>) => t<'k, 'v, 'id>

/** The value stored under `key`, if any. */
let get: (t<'k, 'v, 'id>, 'k) => option<'v>

/** Whether `key` is present. */
let has: (t<'k, 'v, 'id>, 'k) => bool

/** The number of entries. `O(1)`. */
let size: t<'k, 'v, 'id> => int

/** Whether the tree has no entries. */
let isEmpty: t<'k, 'v, 'id> => bool

/** The smallest key, or `None` if the tree is empty. */
let minKey: t<'k, 'v, 'id> => option<'k>

/** The largest key, or `None` if the tree is empty. */
let maxKey: t<'k, 'v, 'id> => option<'k>

/**
The entry at position `index` in ascending key order (0-based), or `None` if `index` is out of
range. `O(log n)`.
*/
let getAt: (t<'k, 'v, 'id>, int) => option<('k, 'v)>

/**
The position (0-based, ascending key order) of `key`, or `None` if it isn't present. `O(log n)`.
*/
let indexOf: (t<'k, 'v, 'id>, 'k) => option<int>

/**
Returns a new tree with `key` set to `value`, overwriting any existing value. If `key` already
holds exactly `value` (`===`), returns `tree` itself, unchanged.
*/
let set: (t<'k, 'v, 'id>, 'k, 'v) => t<'k, 'v, 'id>

/** Returns a new tree with `key` removed, if present; otherwise `tree` itself, unchanged. */
let remove: (t<'k, 'v, 'id>, 'k) => t<'k, 'v, 'id>

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

/**
Computes the difference between `left` and `right`, reporting it via the supplied callbacks:
`onlyLeft`/`onlyRight` for keys found on only one side, and `different` for a key present on
both sides with unequal values (compared with `valueEqual`, which defaults to physical/primitive
equality -- pass a deep-equality function if `'v` needs it). Callbacks are invoked in ascending
key order, and all default to doing nothing. Neither tree is modified.

Stays cheap when `left` and `right` share structure (e.g. one was derived from the other by a
few `set`/`remove` calls): subtrees that are the exact same object in both are skipped without
being looked inside, so the cost is roughly proportional to the number of edits times the
tree's height, not the size of either tree.
*/
let diff: (
  t<'k, 'v, 'id>,
  t<'k, 'v, 'id>,
  ~valueEqual: ('v, 'v) => bool=?,
  ~onlyLeft: ('k, 'v) => unit=?,
  ~onlyRight: ('k, 'v) => unit=?,
  ~different: ('k, 'v, 'v) => unit=?,
) => unit

/**
A diagnostic: counts how many subtrees `diff` would skip whole, by reference, when comparing
`left` against `right`. Not something most callers need; useful for confirming (e.g. in a test)
that two trees derived from a common ancestor actually still share structure.
*/
let sharedSubtreeCount: (t<'k, 'v, 'id>, t<'k, 'v, 'id>) => int

/**
A diagnostic, intended for tests: validates every AVL structural invariant (key order, cached
heights and sizes, balance), throwing a descriptive error if any is violated. See `AvlNode.t`
for the exact list.
*/
let checkInvariants: t<'k, 'v, 'id> => unit
