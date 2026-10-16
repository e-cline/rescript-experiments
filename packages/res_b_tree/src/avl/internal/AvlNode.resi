/***
The AVL tree's node type, and every algorithm that operates directly on it. `AvlTree.res`
is a thin facade over this module and `AvlDiff`; nothing here is meant to be used from
outside this package.

The shape and the balancing scheme follow `Belt.Map`'s own (`Belt_internalAVLtree`): one
entry per node, an empty subtree represented as `None` (compiled to `undefined`, so there
is no wrapper object), and sibling heights allowed to differ by up to 2 rather than the
textbook 1, which costs a slightly taller tree in the worst case for noticeably fewer
rotations. The one addition is `size`, the number of entries in the subtree: that is what
makes `getAt`/`indexOf` `O(log n)`, and what lets `AvlDiff` decide which of two unequal
subtrees to open first.
*/

/**
A non-empty subtree.

Invariants, all validated by `checkInvariants`:

- every key under `left` is less than `key`, and every key under `right` is greater;
- `height` is 1 more than the taller of `left` and `right` (an empty subtree's height is 0);
- the heights of `left` and `right` differ by at most 2;
- `size` is 1 more than the sizes of `left` and `right` together.

Nodes are never mutated once built.
*/
type rec t<'k, 'v> = {
  key: 'k,
  value: 'v,
  height: int,
  size: int,
  left: option<t<'k, 'v>>,
  right: option<t<'k, 'v>>,
}

/** A possibly-empty subtree; `None` is the empty one. */
type tree<'k, 'v> = option<t<'k, 'v>>

/** The number of entries in `tree`. `O(1)`. */
let size: tree<'k, 'v> => int

/** The value stored under the key, if any. */
let get: (tree<'k, 'v>, 'k, ~compare: ('k, 'k) => int) => option<'v>

/** Whether the key is present. */
let has: (tree<'k, 'v>, 'k, ~compare: ('k, 'k) => int) => bool

/** The smallest key in a non-empty subtree. */
let minKey: t<'k, 'v> => 'k

/** The largest key in a non-empty subtree. */
let maxKey: t<'k, 'v> => 'k

/**
The entry at position `index` (0-based, ascending key order). `index` must be within
`[0, node.size)`: the caller checks the range once, so the descent doesn't have to.
*/
let getAt: (t<'k, 'v>, int) => ('k, 'v)

/** The position (0-based, ascending key order) of the key, or `None` if it isn't present. */
let indexOf: (tree<'k, 'v>, 'k, ~compare: ('k, 'k) => int) => option<int>

/**
The tree with the key set to the value. Only the nodes on the path to the key are rebuilt;
every other node is shared with `tree`. If the key already holds that exact value (`===`),
nothing is rebuilt at all and the result is `tree`'s own root node.
*/
let set: (tree<'k, 'v>, 'k, 'v, ~compare: ('k, 'k) => int) => t<'k, 'v>

/**
The tree with the key removed, sharing every node off the path to it with `tree`. If the key
isn't present, the result is `tree` itself (`===`).
*/
let remove: (tree<'k, 'v>, 'k, ~compare: ('k, 'k) => int) => tree<'k, 'v>

/**
Builds a perfectly balanced tree, in `O(n)`, from entries that are already in strictly
ascending key order. The caller is responsible for checking that they are.
*/
let fromSortedArray: array<('k, 'v)> => tree<'k, 'v>

/** Calls the callback for every entry, in ascending key order. */
let forEach: (tree<'k, 'v>, ('k, 'v) => unit) => unit

/** Folds over every entry, in ascending key order. */
let reduce: (tree<'k, 'v>, 'acc, ('acc, 'k, 'v) => 'acc) => 'acc

/** All entries, sorted ascending by key. */
let toArray: tree<'k, 'v> => array<('k, 'v)>

/** All keys, in ascending order. */
let keysArray: tree<'k, 'v> => array<'k>

/** All values, in ascending order of their keys. */
let valuesArray: tree<'k, 'v> => array<'v>

/**
Validates every invariant listed on `t`, for every node in `tree`, throwing a descriptive
error at the first violation.
*/
let checkInvariants: (tree<'k, 'v>, ~compare: ('k, 'k) => int) => unit
