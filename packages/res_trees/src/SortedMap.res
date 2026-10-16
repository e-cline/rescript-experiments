/***
The interfaces every tree in this package shares, as module types: `BTree`, `AvlTree` and
`ChunkTree` are each a `Persistent`, and `MutableBTree`, `MutableAvlTree` and `MutableChunkTree`
each a `Mutable`. Code that should work with any of them, such as a test suite or a benchmark,
takes one of these as a functor argument.

There are only signatures here, no implementation: each tree has its own, since what makes one
faster than another at some operation is exactly what can't be shared.

Constructors are left to each tree, outside `Reads`, `Persistent` and `Mutable`, because they
differ: `BTree.make` also takes an optional `~maxNodeSize`, and a function with an extra optional
argument doesn't match a signature without it. `S` is `Persistent` with the constructors that take
only a comparator, which `AvlTree` and `ChunkTree` have.

## Keys

Keys are identified the same way `Belt.Set`/`Belt.Map` do: via a `Belt.Id.comparable`, built with
`Belt.Id.MakeComparable`, rather than a bare `(k, k) => int` function. Two trees built from
different comparators have different `'id` types, so passing them to `diff`/`sharedSubtreeCount`
together is a compile error, not a wrong answer.
*/

/** What reads a tree, the same whether the tree is persistent or mutable. */
module type Reads = {
  /**
  A sorted map from keys `'k` to values `'v`; `'id` identifies the key comparator (see the module
  comment).
  */
  type t<'k, 'v, 'id>

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
  A diagnostic, intended for tests: validates every structural invariant of the tree (key order,
  cached sizes, balance, how full each node is: each tree's module comment and node module say
  exactly which), throwing a descriptive error if any is violated. Call it after every edit in a
  stress test to catch a structural bug at the point it was introduced.
  */
  let checkInvariants: t<'k, 'v, 'id> => unit
}

/**
A persistent (immutable) tree: every edit returns a new tree, sharing every node off the path to
whatever changed with the original, and leaves the original as it was.
*/
module type Persistent = {
  include Reads

  /**
  Returns a new tree with `key` set to `value`, overwriting any existing value. If `key` already
  holds exactly `value` (`===`), returns `tree` itself, unchanged.
  */
  let set: (t<'k, 'v, 'id>, 'k, 'v) => t<'k, 'v, 'id>

  /** Returns a new tree with `key` removed, if present; otherwise `tree` itself, unchanged. */
  let remove: (t<'k, 'v, 'id>, 'k) => t<'k, 'v, 'id>

  /**
  Computes the difference between `left` and `right`, reporting it via the supplied callbacks:
  `onlyLeft`/`onlyRight` for keys found on only one side, and `different` for a key present on
  both sides with unequal values (compared with `valueEqual`, which defaults to physical/primitive
  equality -- pass a deep-equality function if `'v` needs it). Callbacks are invoked in ascending
  key order, and all default to doing nothing. Neither tree is modified.

  Stays cheap when `left` and `right` share structure (e.g. one was derived from the other by a
  few `set`/`remove` calls): subtrees that are the exact same object in both are skipped without
  being looked inside, so the cost is roughly proportional to the number of edits (times the
  tree's height), not the size of either tree. Each tree's module comment says what more it skips.
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
}

/** `Persistent`, with constructors that take only the comparator: `AvlTree`'s and `ChunkTree`'s. */
module type S = {
  include Persistent

  /** An empty tree, ordered by the comparator in `id`. */
  let make: (~id: Belt.Id.comparable<'k, 'id>) => t<'k, 'v, 'id>

  /**
  Builds a tree from `entries`; later duplicate keys overwrite earlier ones. `O(n)` if `entries`
  is already in strictly ascending key order, `O(n log n)` (repeated `set`) otherwise.
  */
  let fromArray: (~id: Belt.Id.comparable<'k, 'id>, array<('k, 'v)>) => t<'k, 'v, 'id>
}

/**
A mutable tree: `set`/`remove` change it in place. Each is a thin wrapper around a persistent
tree, storing each edit's result back into a single mutable cell, so that `snapshot` is free.

A module of this type is used with `persistent` substituted away by the persistent tree it wraps
(`include SortedMap.Mutable with type persistent<'k, 'v, 'id> := AvlTree.t<'k, 'v, 'id>`), so
`snapshot` returns that tree's own type.
*/
module type Mutable = {
  include Reads

  /** The persistent tree this one wraps, which `snapshot` returns. */
  type persistent<'k, 'v, 'id>

  /** Sets `key` to `value` in place, overwriting any existing value. */
  let set: (t<'k, 'v, 'id>, 'k, 'v) => unit

  /** Removes `key` in place, if present; a no-op if it isn't. */
  let remove: (t<'k, 'v, 'id>, 'k) => unit

  /**
  A cheap (`O(1)`), always-safe-to-keep persistent snapshot of the tree's current contents, so
  that diffing "this tree's contents right now" against "what it looked like earlier" is just the
  persistent tree's `diff` on two snapshots.

  It stays safe because nothing ever mutates a persistent tree's nodes in place: only this tree's
  own cell changes, and only to point at a new, independent persistent tree. So the snapshot keeps
  looking exactly like the tree did at that moment, however much the mutable tree is edited
  afterward.
  */
  let snapshot: t<'k, 'v, 'id> => persistent<'k, 'v, 'id>
}
