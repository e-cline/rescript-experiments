/***
A persistent (immutable) B-tree: an ordered `('k, 'v)` collection, sorted by key, that
never mutates in place. Every operation that would change the collection (`set`, `remove`)
returns a *new* `t`, sharing as much structure with the original as possible. For a mutable,
in-place-feeling API on top of the same tree, see `MutableBTree`.

`t` is opaque here, so nothing outside this file (including `MutableBTree.res`) can depend on
its representation -- the raw node tree, the extracted comparator, ... -- only on the functions
below. The implementation is under `internal/` (`Node`, `Insert`, `Delete`, `Diff`, `ArrayOps`);
`root` is the one way in, for this package's own tests.

## Keys

Keys are identified the same way `Belt.Set`/`Belt.Map` do: via a `Belt.Id.comparable`,
built with `Belt.Id.MakeComparable`, rather than a bare `(k, k) => int` comparator
function. That also means two trees built from *different* comparators can never
accidentally be compared against each other: `diff`/`sharedSubtreeCount` require both
trees to share the same `'id` type parameter, so mixing them is a compile error, not a
runtime one.

## Structural sharing

Because `set`/`remove` only rebuild the nodes on the path from the root to whatever
changed, and never touch anything else, two trees derived from a common ancestor still
literally share node objects outside the edited region. `diff` exploits that to stay cheap
(see its own comment).
*/

/**
A persistent B-tree from keys `'k` to values `'v`; `'id` identifies the key comparator (see
the module comment).
*/
type t<'k, 'v, 'id>

/**
An empty tree, ordered by the comparator in `id`.

`maxNodeSize` is the maximum number of entries per leaf (and children per internal node)
before it splits, and defaults to `32`. A value below `4` leaves no room for the borrow/merge
deletion logic to do its job (a node couldn't have a meaningful "spare" sibling to borrow from),
so it falls back to the default instead; a value above `256` buys nothing but wasted array
copies on every edit, so it is clamped down to `256`.
*/
let make: (~id: Belt.Id.comparable<'k, 'id>, ~maxNodeSize: int=?) => t<'k, 'v, 'id>

/**
Builds a tree from `entries`; later duplicate keys overwrite earlier ones. `maxNodeSize` is as in
`make`. `O(n)` if `entries` is already in strictly ascending key order (the leaves are then built
full, directly), `O(n log n)` (repeated `set`) otherwise.
*/
let fromArray: (
  ~id: Belt.Id.comparable<'k, 'id>,
  ~maxNodeSize: int=?,
  array<('k, 'v)>,
) => t<'k, 'v, 'id>

/** The value stored under `key`, if any. */
let get: (t<'k, 'v, 'id>, 'k) => option<'v>

/** Whether `key` is present. */
let has: (t<'k, 'v, 'id>, 'k) => bool

/** The number of entries. `O(1)`. */
let size: t<'k, 'v, 'id> => int

/** Whether the tree has no entries. */
let isEmpty: t<'k, 'v, 'id> => bool

/**
The maximum node size this tree is actually using, after `make`'s clamping (see `make`).
Exposed mainly so tests can confirm that clamping behavior without needing access to the
tree's internal representation.
*/
let maxNodeSize: t<'k, 'v, 'id> => int

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
holds exactly `value` (`===`), returns `tree` itself, unchanged. Overwriting keeps the key object
the tree already held, which the comparator considers equal to `key`.
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
being looked inside, so the cost is roughly proportional to the number of edits, not the size of
either tree. Leaves that share their `keys` array, as an overwrite leaves them, are compared by
value alone, without calling the comparator; values that are `===` are taken as equal without
calling `valueEqual`.
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
For this package's own tests only: the tree's root node, so that they can check its shape (where
nodes split, borrow and merge, and which arrays an edit reuses). `Node` is internal, and nothing
about it is promised.
*/
let root: t<'k, 'v, 'id> => option<Node.t<'k, 'v>>

/**
A diagnostic, intended for tests: validates every B-tree structural invariant (key order,
separators, cached counts, how full each node is, uniform depth), throwing a descriptive error if
any is violated; see `Node.res` for the exact list. Call it after every mutation in a stress test
to catch a structural bug at the point it was introduced.
*/
let checkInvariants: t<'k, 'v, 'id> => unit
