/***
A persistent (immutable) B-tree: an ordered `('k, 'v)` collection, sorted by key, that
never mutates in place. Every operation that would change the collection (`set`, `remove`)
returns a *new* `t`, sharing as much structure with the original as possible. For a mutable,
in-place-feeling API on top of the same tree, see `MutableBTree`.

Its interface is `SortedMap.Persistent`, where each operation is documented, plus the
constructors, `maxNodeSize` and `root` below. `t` is opaque here, so nothing outside this file
(including `MutableBTree.res`) can depend on its representation -- the raw node tree, the
extracted comparator, ... -- only on those functions. The implementation is under `internal/`
(`Node`, `Insert`, `Delete`, `Diff`, `ArrayOps`); `root` is the one way in, for this package's
own tests.

## Keys

Keys are identified the same way `Belt.Set`/`Belt.Map` do: via a `Belt.Id.comparable`,
built with `Belt.Id.MakeComparable`, rather than a bare `(k, k) => int` comparator
function. That also means two trees built from *different* comparators can never
accidentally be compared against each other: `diff`/`sharedSubtreeCount` require both
trees to share the same `'id` type parameter, so mixing them is a compile error, not a
runtime one.

`set` overwriting a key keeps the key object the tree already held, which the comparator
considers equal to the one passed.

## Structural sharing

Because `set`/`remove` only rebuild the nodes on the path from the root to whatever
changed, and never touch anything else, two trees derived from a common ancestor still
literally share node objects outside the edited region. `diff` exploits that to stay cheap:
its cost is roughly proportional to the number of edits. Leaves that share their `keys` array,
as an overwrite leaves them, are compared by value alone, without calling the comparator; and
values that are `===` are taken as equal without calling `valueEqual`.

## Invariants

`checkInvariants` checks key order, separators, cached counts, how full each node is and
uniform depth. See `Node.res` for the exact list.
*/

include SortedMap.Persistent

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

/**
The maximum node size this tree is actually using, after `make`'s clamping (see `make`).
Exposed mainly so tests can confirm that clamping behavior without needing access to the
tree's internal representation.
*/
let maxNodeSize: t<'k, 'v, 'id> => int

/**
For this package's own tests only: the tree's root node, so that they can check its shape (where
nodes split, borrow and merge, and which arrays an edit reuses). `Node` is internal, and nothing
about it is promised.
*/
let root: t<'k, 'v, 'id> => option<Node.t<'k, 'v>>
