/***
`BTree`'s node, and everything that only reads one. `Insert`, `Delete` and `Diff` are the rest of
the implementation; `BTree` is the public face.

## One shape for both kinds of node

Leaves and internal nodes are the same record, with the fields a kind doesn't use holding one
shared empty array:

|          | leaf                | internal node                                             |
| -------- | ------------------- | --------------------------------------------------------- |
| `keys`   | the keys, ascending | the separators, ascending                                 |
| `values` | the values, aligned | (empty)                                                   |
| `links`  | (empty)             | each child followed by a count, one pair more than `keys` |

The alternative, a variant with an inline record per kind, compiles to two differently shaped
objects told apart by a string `TAG`. A descent would then load `keys` from two object shapes at
one site. With one shape, every field load in a descent sees a single hidden class, and "is this a
leaf" is one load and a pointer comparison (`links` against the shared empty array) rather than a
string comparison. Every node is built by `leaf` or `internal` below so that the fields are always
written in the same order. The price is one unused field per node (4 bytes).

## Sizes: cumulative counts, interleaved with the children

`links` holds, for each child in turn, the child and then the number of entries in that child and
all those before it: `[child0, count0, child1, count1, ...]`. A subtree's size is its last count,
so nothing more is stored for it.

*Interleaved*, because the cost of an edit to a node is mostly the number of arrays it has to
copy, not their length: copying a second array costs a second call and a second allocation, where
copying one array twice as long costs a few nanoseconds more. So an edit below a node copies
exactly one of its arrays, `links`, whether it changes a size or not; `keys` is reused unless a
child split, borrowed or merged. (This tree's earlier layout, with separate `children` and `sizes`
arrays, copied both for every insertion or removal.)

*Cumulative*, so that reading by position stays cheap:

- `getAt` binary-searches the counts for the child holding a position (rather than walking per-child
  sizes from the left, subtracting);
- `indexOf` reads the number of entries to the left of the child it descends into with one load
  (rather than adding up the sizes of every child to the left).

The price of cumulative counts is that an insertion or removal adjusts every count from the edited
child onwards, in the copy it has just made: at most `maxNodeSize` additions on small integers
already in cache.

Storing no sizes in the parent at all (each node holding only its own total) would also be one
array per level, but `getAt` and `indexOf` would then load a field from up to `maxNodeSize`
separate child objects per level.

`links` mixes nodes and integers, so it is an array of an unboxed variant, which costs nothing at
run time: a `Child` is the node itself and a `Count` the integer itself. Which is which is known
from the position, so they are read back with `childAt` and `countAt` rather than by matching.

## Invariants

- A leaf holds at least one key, strictly ascending, with `values` the same length.
- `keys[i]` of an internal node is a routing boundary: every key under child `i` is less than it,
  and every key under child `i + 1` is greater than or equal to it. It need not be a key the tree
  holds (removing a leaf's smallest key leaves the boundary above it in place).
- Every node but the root has between `minNodeSize` and `maxNodeSize` keys (a leaf) or children
  (an internal node). A root leaf has at least one key; a root internal node, at least two
  children.
- Every leaf is at the same depth.
*/

type rec t<'k, 'v> = {
  keys: array<'k>,
  values: array<'v>,
  links: array<link<'k, 'v>>,
}
@unboxed
and link<'k, 'v> =
  | Child(t<'k, 'v>)
  | Count(int)

external toChild: link<'k, 'v> => t<'k, 'v> = "%identity"
external toCount: link<'k, 'v> => int = "%identity"

/**
The one empty array that stands in every unused field. Never written to. A node is a leaf exactly
when its `links` is this array.
*/
let sharedEmpty: array<int> = []

external emptyOf: array<int> => array<'a> = "%identity"

let leaf = (keys: array<'k>, values: array<'v>): t<'k, 'v> => {
  keys,
  values,
  links: emptyOf(sharedEmpty),
}

let internal = (keys: array<'k>, links: array<link<'k, 'v>>): t<'k, 'v> => {
  keys,
  values: emptyOf(sharedEmpty),
  links,
}

let isLeaf = (node: t<'k, 'v>): bool => node.links === emptyOf(sharedEmpty)

/** The child at position `index` among the children in `links`. */
let childAt = (links: array<link<'k, 'v>>, index: int): t<'k, 'v> =>
  toChild(Array.getUnsafe(links, Int.shiftLeft(index, 1)))

/** The number of entries in the children at positions 0 to `index` together. */
let countAt = (links: array<link<'k, 'v>>, index: int): int =>
  toCount(Array.getUnsafe(links, Int.shiftLeft(index, 1) + 1))

let setChild = (links: array<link<'k, 'v>>, index: int, child: t<'k, 'v>): unit =>
  Array.setUnsafe(links, Int.shiftLeft(index, 1), Child(child))

let setCount = (links: array<link<'k, 'v>>, index: int, count: int): unit =>
  Array.setUnsafe(links, Int.shiftLeft(index, 1) + 1, Count(count))

/** How many children `links` holds. */
let childCount = (links: array<link<'k, 'v>>): int => Int.shiftRight(Array.length(links), 1)

/** Adds `delta` to the count of every child from position `from` onwards, in place. */
let addToCounts = (links: array<link<'k, 'v>>, from: int, delta: int): unit => {
  let position = ref(Int.shiftLeft(from, 1) + 1)
  let length = Array.length(links)
  while position.contents < length {
    Array.setUnsafe(
      links,
      position.contents,
      Count(toCount(Array.getUnsafe(links, position.contents)) + delta),
    )
    position := position.contents + 2
  }
}

/** The children of an internal node, as an array of their own. For tests and diagnostics. */
let children = (node: t<'k, 'v>): array<t<'k, 'v>> =>
  Belt.Array.makeBy(childCount(node.links), index => childAt(node.links, index))

/** The cumulative counts of an internal node, as an array of their own. For tests and diagnostics. */
let counts = (node: t<'k, 'v>): array<int> =>
  Belt.Array.makeBy(childCount(node.links), index => countAt(node.links, index))

/** The number of keys in a leaf, or of children in an internal node. */
let width = (node: t<'k, 'v>): int =>
  isLeaf(node) ? Array.length(node.keys) : childCount(node.links)

/** The number of entries in the whole subtree. */
let size = (node: t<'k, 'v>): int =>
  isLeaf(node)
    ? Array.length(node.keys)
    : toCount(Array.getUnsafe(node.links, Array.length(node.links) - 1))

/** How many levels of internal nodes there are above the leaves of this subtree. */
let rec height = (node: t<'k, 'v>, above: int): int =>
  isLeaf(node) ? above : height(childAt(node.links, 0), above + 1)

// -----------------------------------------------------------------------------
// Search
// -----------------------------------------------------------------------------

/**
The widest stretch of keys that `search` scans from one end rather than halving. Halving costs a
branch that cannot be predicted at every step; a scan costs one such branch in total, where it
stops. With keys that are cheap to compare, the scan wins at this width (in a coarse measurement,
replacing a pure binary search by this made `get` on integer keys roughly a quarter faster at
each of the node sizes 8, 16 and 32). Halving down to it first keeps the number of comparator
calls close to a binary search's when nodes are wide: at most 2 + 8 for a node of 32, and about 6
on average against 5.
*/
let scanWidth = 8

/**
The scanning part of `search`, over `keys[index, high)`: stops at the first key not below `key`,
and so learns whether it is equal to it from the same comparison.
*/
let rec scan = (keys: array<'k>, key: 'k, compare: ('k, 'k) => int, index: int, high: int): int =>
  if index >= high {
    Int.bitwiseNot(high)
  } else {
    let comparison = compare(Array.getUnsafe(keys, index), key)
    if comparison >= 0 {
      comparison == 0 ? index : Int.bitwiseNot(index)
    } else {
      scan(keys, key, compare, index + 1, high)
    }
  }

/**
Searches the ascending `keys` for `key`: its index if it is there, and otherwise the bitwise
complement (so, a negative number) of the index it would be inserted at.

The one search of every descent, shared by leaves and internal nodes (see `childIndex` for what
the result means in an internal node). A binary search down to a stretch of `scanWidth` keys,
then a scan of that stretch.

The shape of this matters more than it looks (all of it measured coarsely, on integer keys):

- `scan` returns as soon as it has its answer. Two loops in this one function, with a flag in
  place of that early return, were about a third slower; so was a single loop doing both phases.
- `scan` is called from two places here. With one caller, the minifier the benchmarks are built
  with inlines it as a function expression called on the spot, which allocates a closure on every
  search (see "Single callers" in `BTree`).
*/
let search = (keys: array<'k>, key: 'k, compare: ('k, 'k) => int): int => {
  let length = Array.length(keys)
  if length <= scanWidth {
    scan(keys, key, compare, 0, length)
  } else {
    let low = ref(0)
    let high = ref(length)
    // Everything before `low` is below `key`, and `high` is the end or a key above it.
    while high.contents - low.contents > scanWidth {
      let middle = Int.shiftRightUnsigned(low.contents + high.contents, 1)
      if compare(Array.getUnsafe(keys, middle), key) <= 0 {
        low := middle
      } else {
        high := middle
      }
    }
    scan(keys, key, compare, low.contents, high.contents)
  }
}

/**
Which child of an internal node a key belongs under, given what `search` said of its separators.
A key equal to separator `i` belongs to the right of it, in child `i + 1`; a key not among the
separators belongs in the child at its insertion index.
*/
let childIndex = (searchResult: int): int =>
  searchResult >= 0 ? searchResult + 1 : Int.bitwiseNot(searchResult)

let rec minKey = (node: t<'k, 'v>): 'k =>
  isLeaf(node) ? Array.getUnsafe(node.keys, 0) : minKey(childAt(node.links, 0))

let rec maxKey = (node: t<'k, 'v>): 'k =>
  isLeaf(node)
    ? Array.getUnsafe(node.keys, Array.length(node.keys) - 1)
    : maxKey(childAt(node.links, childCount(node.links) - 1))

// -----------------------------------------------------------------------------
// Traversal
// -----------------------------------------------------------------------------

let rec forEach = (node: t<'k, 'v>, callback: ('k, 'v) => unit): unit =>
  if isLeaf(node) {
    let {keys, values} = node
    for index in 0 to Array.length(keys) - 1 {
      callback(Array.getUnsafe(keys, index), Array.getUnsafe(values, index))
    }
  } else {
    let links = node.links
    for index in 0 to childCount(links) - 1 {
      forEach(childAt(links, index), callback)
    }
  }

let rec reduce = (node: t<'k, 'v>, initial: 'acc, callback: ('acc, 'k, 'v) => 'acc): 'acc => {
  let accumulator = ref(initial)
  if isLeaf(node) {
    let {keys, values} = node
    for index in 0 to Array.length(keys) - 1 {
      accumulator :=
        callback(accumulator.contents, Array.getUnsafe(keys, index), Array.getUnsafe(values, index))
    }
  } else {
    let links = node.links
    for index in 0 to childCount(links) - 1 {
      accumulator := reduce(childAt(links, index), accumulator.contents, callback)
    }
  }
  accumulator.contents
}

/** Appends every key of the subtree to `into`. */
let rec pushKeys = (node: t<'k, 'v>, into: array<'k>): unit =>
  if isLeaf(node) {
    let keys = node.keys
    for index in 0 to Array.length(keys) - 1 {
      Array.push(into, Array.getUnsafe(keys, index))
    }
  } else {
    let links = node.links
    for index in 0 to childCount(links) - 1 {
      pushKeys(childAt(links, index), into)
    }
  }

/** Appends every value of the subtree to `into`. */
let rec pushValues = (node: t<'k, 'v>, into: array<'v>): unit =>
  if isLeaf(node) {
    let values = node.values
    for index in 0 to Array.length(values) - 1 {
      Array.push(into, Array.getUnsafe(values, index))
    }
  } else {
    let links = node.links
    for index in 0 to childCount(links) - 1 {
      pushValues(childAt(links, index), into)
    }
  }

/** Appends every entry of the subtree to `into`. */
let rec pushEntries = (node: t<'k, 'v>, into: array<('k, 'v)>): unit =>
  if isLeaf(node) {
    let {keys, values} = node
    for index in 0 to Array.length(keys) - 1 {
      Array.push(into, (Array.getUnsafe(keys, index), Array.getUnsafe(values, index)))
    }
  } else {
    let links = node.links
    for index in 0 to childCount(links) - 1 {
      pushEntries(childAt(links, index), into)
    }
  }

// -----------------------------------------------------------------------------
// Building from sorted entries
// -----------------------------------------------------------------------------

/**
Builds a tree bottom-up from entries already in strictly ascending key order, or `None` if there
are none. Each level is filled as full as it can be while keeping its nodes the same size to
within one: `ceil(count / maxNodeSize)` nodes.

The whole level is first gathered into scratch arrays (grown with `push`, which is fine for
arrays that are thrown away), and each node's arrays are then sliced out of those: a slice of a
packed array is packed and exactly sized.
*/
let fromSorted = (entries: array<('k, 'v)>, ~maxNodeSize: int): option<t<'k, 'v>> => {
  let entryCount = Array.length(entries)
  if entryCount == 0 {
    None
  } else {
    let allKeys = []
    let allValues = []
    for index in 0 to entryCount - 1 {
      let (key, value) = Array.getUnsafe(entries, index)
      Array.push(allKeys, key)
      Array.push(allValues, value)
    }
    // The current level, left to right: each node followed by its own size (the layout of
    // `links`, but for the counts not yet being cumulative), and the smallest key under each.
    let level = ref([])
    let smallestKeys = ref([])
    let leafCount = (entryCount + maxNodeSize - 1) / maxNodeSize
    let start = ref(0)
    for leafIndex in 0 to leafCount - 1 {
      let width = entryCount / leafCount + (leafIndex < mod(entryCount, leafCount) ? 1 : 0)
      let end = start.contents + width
      Array.push(
        level.contents,
        Child(
          leaf(
            ArrayOps.slice(allKeys, start.contents, end),
            ArrayOps.slice(allValues, start.contents, end),
          ),
        ),
      )
      Array.push(level.contents, Count(width))
      Array.push(smallestKeys.contents, Array.getUnsafe(allKeys, start.contents))
      start := end
    }
    while Array.length(level.contents) > 2 {
      let below = level.contents
      let belowKeys = smallestKeys.contents
      let belowCount = childCount(below)
      let parentCount = (belowCount + maxNodeSize - 1) / maxNodeSize
      let parents = []
      let parentKeys = []
      let start = ref(0)
      for parentIndex in 0 to parentCount - 1 {
        let width = belowCount / parentCount + (parentIndex < mod(belowCount, parentCount) ? 1 : 0)
        let end = start.contents + width
        let links = ArrayOps.slice(below, start.contents * 2, end * 2)
        for index in 1 to width - 1 {
          setCount(links, index, countAt(links, index) + countAt(links, index - 1))
        }
        Array.push(
          parents,
          Child(internal(ArrayOps.slice(belowKeys, start.contents + 1, end), links)),
        )
        Array.push(parents, Count(countAt(links, width - 1)))
        Array.push(parentKeys, Array.getUnsafe(belowKeys, start.contents))
        start := end
      }
      level := parents
      smallestKeys := parentKeys
    }
    Some(childAt(level.contents, 0))
  }
}

// -----------------------------------------------------------------------------
// Invariants
// -----------------------------------------------------------------------------

@val external isArray: 'a => bool = "Array.isArray"

/**
Validates the subtree against every invariant in the module comment, given the bounds its
ancestors' separators put on its keys (`lower` inclusive, `upper` exclusive; `None` for no bound).
Returns the number of entries it really holds and the height of its leaves. Throws on the first
violation.
*/
let rec check = (
  node: t<'k, 'v>,
  ~compare: ('k, 'k) => int,
  ~minSize: int,
  ~maxSize: int,
  ~isRoot: bool,
  ~lower: option<'k>,
  ~upper: option<'k>,
): (int, int) => {
  let fail = (message: string) => JsError.throwWithMessage(`BTree.checkInvariants: ${message}`)
  let {keys, values, links} = node
  if !isArray(keys) || !isArray(values) || !isArray(links) {
    fail("a node field is not an array")
  }
  let keyCount = Array.length(keys)
  for index in 1 to keyCount - 1 {
    if compare(Array.getUnsafe(keys, index - 1), Array.getUnsafe(keys, index)) >= 0 {
      fail(`keys out of order at index ${Int.toString(index)}`)
    }
  }

  // With the keys ascending, the first and last are the only ones the bounds need checking
  // against.
  if keyCount > 0 {
    switch lower {
    | Some(bound) if isLeaf(node) && compare(Array.getUnsafe(keys, 0), bound) < 0 =>
      fail("a leaf holds a key below the separator to its left")
    | Some(bound) if !isLeaf(node) && compare(Array.getUnsafe(keys, 0), bound) <= 0 =>
      fail("a separator is not above the separator to its left one level up")
    | _ => ()
    }
    switch upper {
    | Some(bound) if compare(Array.getUnsafe(keys, keyCount - 1), bound) >= 0 =>
      fail("a key or separator is not below the separator to its right one level up")
    | _ => ()
    }
  }
  let checkOccupancy = (count: int, least: int, what: string) => {
    if count < least {
      fail(`${what}: ${Int.toString(count)}, fewer than the minimum ${Int.toString(least)}`)
    }
    if count > maxSize {
      fail(`${what}: ${Int.toString(count)}, more than the maximum ${Int.toString(maxSize)}`)
    }
  }
  if isLeaf(node) {
    if Array.length(values) != keyCount {
      fail(
        `a leaf has ${Int.toString(keyCount)} keys but ${Int.toString(
            Array.length(values),
          )} values`,
      )
    }
    checkOccupancy(keyCount, isRoot ? 1 : minSize, "leaf key count")
    (keyCount, 0)
  } else {
    if values !== emptyOf(sharedEmpty) {
      fail("an internal node has values")
    }
    if mod(Array.length(links), 2) != 0 {
      fail("an internal node's links are not pairs of a child and a count")
    }
    let children = childCount(links)
    if keyCount != children - 1 {
      fail(
        `an internal node has ${Int.toString(children)} children but ${Int.toString(
            keyCount,
          )} separators`,
      )
    }
    checkOccupancy(children, isRoot ? 2 : minSize, "internal node child count")
    let total = ref(0)
    let leafHeight = ref(-1)
    for index in 0 to children - 1 {
      if (
        Type.typeof(childAt(links, index)) != #object ||
          Type.typeof(countAt(links, index)) != #number
      ) {
        fail(`link pair ${Int.toString(index)} is not a child and a count`)
      }
      let (childSize, childHeight) = check(
        childAt(links, index),
        ~compare,
        ~minSize,
        ~maxSize,
        ~isRoot=false,
        ~lower=index == 0 ? lower : Some(Array.getUnsafe(keys, index - 1)),
        ~upper=index == children - 1 ? upper : Some(Array.getUnsafe(keys, index)),
      )
      if leafHeight.contents == -1 {
        leafHeight := childHeight
      } else if childHeight != leafHeight.contents {
        fail(
          `leaves at different depths: child ${Int.toString(index)} has height ${Int.toString(
              childHeight,
            )}, the children before it ${Int.toString(leafHeight.contents)}`,
        )
      }
      total := total.contents + childSize
      if countAt(links, index) != total.contents {
        fail(
          `count ${Int.toString(countAt(links, index))} at child ${Int.toString(
              index,
            )} should be ${Int.toString(total.contents)}`,
        )
      }
    }
    (total.contents, leafHeight.contents + 1)
  }
}
