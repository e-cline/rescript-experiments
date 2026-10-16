// The node of a leaf-chunked AVL tree: a height-balanced binary spine, as in
// `AvlNode.res`, whose leaves are small sorted arrays rather than single entries.
// Entries live only in leaves; an internal node holds a separator key and two
// non-empty children.
//
// ## One record for both kinds of node
//
// A leaf and an internal node are the same record, so that every node has the
// same object shape and each property read in a descent (`height`, `key`,
// `left`, `right`, `size`) sees a single hidden class. The alternative, a
// variant with two inline records, compiles to two shapes told apart by a string
// `TAG`, and would need a switch just to read `size` or `height`. The price is
// that each kind carries the other's fields, unused:
//
// - A leaf has `height == 1`, its entries in `keys`/`values` (parallel, sorted
//   ascending by key, never empty in a tree), `size` equal to their length, and
//   `key` equal to `keys[0]`. Its `left` and `right` are `undefined` and must
//   never be read: every function here checks `height` first.
// - An internal node has `height > 1`, both children, `size` and `height`
//   derived from them, and `keys`/`values` pointing at one shared empty array.
//   Its `key` is the separator: every key under `left` is less than it, and
//   every key under `right` is greater than or equal to it. It is the smallest
//   key under `right` when the node is built, but a later removal of that key
//   leaves it in place, so it need not be a key the tree still holds.
//
// ## Balance
//
// The spine is balanced exactly as `AvlNode` is: sibling heights differ by at
// most 2, and an edit only reaches `balance` where the subtree it replaced
// changed height.
//
// ## Leaf occupancy
//
// A leaf holds at most `max` entries, and at least `max / 2` unless it is the
// root. Inserting into a full leaf splits the `max + 1` entries evenly into two
// leaves under a new internal node. A removal that takes a leaf below the
// minimum is repaired by its parent, using the neighbouring leaf on the other
// side of the parent's separator (the first leaf of the right subtree or the
// last of the left): if the two together hold fewer than `max` entries they
// become one leaf and the parent disappears, otherwise their entries are shared
// out evenly between them and the parent's separator moved. Merging only below
// `max`, not at it, leaves the merged leaf room for one insertion before it
// would split again.
//
// ## Arrays
//
// Leaf arrays are always built at their exact length from packed arrays, with
// `slice`, `concat` and `toSpliced`, so that V8 keeps them packed and without
// spare capacity. Overwriting a value copies `values` and shares `keys`, which
// is what lets a diff tell an overwritten leaf from a restructured one without
// comparing any keys.

type rec t<'k, 'v> = {
  key: 'k,
  size: int,
  height: int,
  left: t<'k, 'v>,
  right: t<'k, 'v>,
  keys: array<'k>,
  values: array<'v>,
}

type tree<'k, 'v> = option<t<'k, 'v>>

@send external copy: array<'a> => array<'a> = "slice"
@send external sliceRange: (array<'a>, int, int) => array<'a> = "slice"
@send external sliceFrom: (array<'a>, int) => array<'a> = "slice"
@send external concat: (array<'a>, array<'a>) => array<'a> = "concat"
/** A copy of the array with `item` inserted before the element at `index`. */
@send
external insertAt: (array<'a>, int, @as(0) _, 'a) => array<'a> = "toSpliced"
/** A copy of the array without the element at `index`. */
@send
external removeAt: (array<'a>, int, @as(1) _) => array<'a> = "toSpliced"

// The `keys`/`values` of every internal node. Never written to.
let noEntries: array<unknown> = []
external emptyArray: array<unknown> => array<'a> = "%identity"

// A leaf's `left`/`right`.
external noChild: unit => t<'k, 'v> = "%identity"

// -----------------------------------------------------------------------------
// Construction and balancing
// -----------------------------------------------------------------------------

/** A leaf over two parallel arrays, which it takes ownership of. */
let makeLeaf = (keys: array<'k>, values: array<'v>): t<'k, 'v> => {
  key: Array.getUnsafe(keys, 0),
  size: Array.length(keys),
  height: 1,
  left: noChild(),
  right: noChild(),
  keys,
  values,
}

/** An internal node over two subtrees already known to be balanced against each other. */
let create = (left: t<'k, 'v>, key: 'k, right: t<'k, 'v>): t<'k, 'v> => {
  let leftHeight = left.height
  let rightHeight = right.height
  {
    key,
    size: left.size + right.size,
    height: (leftHeight >= rightHeight ? leftHeight : rightHeight) + 1,
    left,
    right,
    keys: emptyArray(noEntries),
    values: emptyArray(noEntries),
  }
}

/**
An internal node over two subtrees whose heights may differ by up to 3, rotating if they differ
by more than 2. `size` is the number of entries the result will hold. See `AvlNode.balance`,
which this is, with a separator where that has an entry.
*/
let balance = (left: t<'k, 'v>, key: 'k, right: t<'k, 'v>, ~size: int): t<'k, 'v> => {
  let leftHeight = left.height
  let rightHeight = right.height
  if leftHeight > rightHeight + 2 {
    // `left` is at least 4 tall, so it is an internal node.
    let leftLeft = left.left
    let leftRight = left.right
    if leftLeft.height >= leftRight.height {
      create(leftLeft, left.key, create(leftRight, key, right))
    } else {
      // `leftRight` is taller than its sibling, so it is an internal node too.
      create(
        create(leftLeft, left.key, leftRight.left),
        leftRight.key,
        create(leftRight.right, key, right),
      )
    }
  } else if rightHeight > leftHeight + 2 {
    let rightLeft = right.left
    let rightRight = right.right
    if rightRight.height >= rightLeft.height {
      create(create(left, key, rightLeft), right.key, rightRight)
    } else {
      create(
        create(left, key, rightLeft.left),
        rightLeft.key,
        create(rightLeft.right, right.key, rightRight),
      )
    }
  } else {
    {
      key,
      size,
      height: (leftHeight >= rightHeight ? leftHeight : rightHeight) + 1,
      left,
      right,
      keys: emptyArray(noEntries),
      values: emptyArray(noEntries),
    }
  }
}

/**
`node` with its left subtree replaced by `newLeft`, which must be one edit away from the old
one. `size` is the new node's size. As in `AvlNode.replaceLeft`, a replacement of the same
height needs no rebalancing and never looks at the other subtree.
*/
let replaceLeft = (node: t<'k, 'v>, newLeft: t<'k, 'v>, ~size: int): t<'k, 'v> =>
  if newLeft.height == node.left.height {
    {
      key: node.key,
      size,
      height: node.height,
      left: newLeft,
      right: node.right,
      keys: node.keys,
      values: node.values,
    }
  } else {
    balance(newLeft, node.key, node.right, ~size)
  }

/** `replaceLeft`, for the right subtree. */
let replaceRight = (node: t<'k, 'v>, newRight: t<'k, 'v>, ~size: int): t<'k, 'v> =>
  if newRight.height == node.right.height {
    {
      key: node.key,
      size,
      height: node.height,
      left: node.left,
      right: newRight,
      keys: node.keys,
      values: node.values,
    }
  } else {
    balance(node.left, node.key, newRight, ~size)
  }

/**
A tree over entries already in strictly ascending key order, given as parallel packed arrays.
Leaves are filled evenly to about three quarters of `max`, so that the tree is neither sparse nor
about to split everywhere, under a spine split at its midpoint.
*/
let fromSortedArrays = (keys: array<'k>, values: array<'v>, ~max: int): tree<'k, 'v> => {
  let count = Array.length(keys)
  if count == 0 {
    None
  } else {
    let target = max * 3 / 4 > 0 ? max * 3 / 4 : 1
    let wanted = (count + target - 1) / target
    // Rounding the leaf count up can leave every leaf under the minimum; one leaf fewer can't.
    let leafCount = wanted > 1 && count / wanted < max / 2 ? wanted - 1 : wanted
    let base = count / leafCount
    let extra = mod(count, leafCount)
    // The first `extra` leaves hold one entry more than the rest.
    let startOf = leaf => leaf * base + (leaf < extra ? leaf : extra)
    let rec build = (first, last) =>
      if last - first == 1 {
        let start = startOf(first)
        let end = startOf(last)
        makeLeaf(sliceRange(keys, start, end), sliceRange(values, start, end))
      } else {
        let middle = first + (last - first) / 2
        create(build(first, middle), Array.getUnsafe(keys, startOf(middle)), build(middle, last))
      }
    Some(build(0, leafCount))
  }
}

// -----------------------------------------------------------------------------
// Lookup
// -----------------------------------------------------------------------------

/**
Binary search of a leaf's keys: the index of `key` if it is there, and otherwise `-(i + 1)`
where `i` is the index it would be inserted at. Used at every leaf size: a linear scan measured
slower even with leaves of 8, and so did a search that never stops early on finding the key.
*/
let search = (keys: array<'k>, key: 'k, ~compare: ('k, 'k) => int): int => {
  let low = ref(0)
  let high = ref(Array.length(keys))
  let found = ref(-1)
  while found.contents < 0 && low.contents < high.contents {
    let middle = Int.shiftRightUnsigned(low.contents + high.contents, 1)
    let comparison = compare(key, Array.getUnsafe(keys, middle))
    if comparison == 0 {
      found := middle
    } else if comparison < 0 {
      high := middle
    } else {
      low := middle + 1
    }
  }
  found.contents >= 0 ? found.contents : -low.contents - 1
}

/** The leaf that holds `key` if any does. */
let rec findLeaf = (node: t<'k, 'v>, key: 'k, ~compare: ('k, 'k) => int): t<'k, 'v> =>
  if node.height == 1 {
    node
  } else {
    findLeaf(compare(key, node.key) < 0 ? node.left : node.right, key, ~compare)
  }

let rec minLeaf = (node: t<'k, 'v>): t<'k, 'v> => node.height == 1 ? node : minLeaf(node.left)
let rec maxLeaf = (node: t<'k, 'v>): t<'k, 'v> => node.height == 1 ? node : maxLeaf(node.right)

// -----------------------------------------------------------------------------
// Insertion
// -----------------------------------------------------------------------------

/**
`node` with `key` set to `value`. At the leaf: the same leaf if nothing changes, a leaf sharing
its `keys` if a value is overwritten, a longer leaf if there is room, and otherwise an internal
node over two leaves. Above it, the same node if the child came back unchanged.
*/
let rec set = (node: t<'k, 'v>, key: 'k, value: 'v, ~compare: ('k, 'k) => int, ~max: int): t<
  'k,
  'v,
> =>
  if node.height == 1 {
    let keys = node.keys
    let values = node.values
    let index = search(keys, key, ~compare)
    if index >= 0 {
      if Array.getUnsafe(values, index) === value {
        node
      } else {
        let newValues = copy(values)
        Array.setUnsafe(newValues, index, value)
        {
          key: node.key,
          size: node.size,
          height: 1,
          left: noChild(),
          right: noChild(),
          keys,
          values: newValues,
        }
      }
    } else {
      let position = -index - 1
      let newKeys = insertAt(keys, position, key)
      let newValues = insertAt(values, position, value)
      let count = Array.length(newKeys)
      if count <= max {
        makeLeaf(newKeys, newValues)
      } else {
        let middle = (count + 1) / 2
        let right = makeLeaf(sliceFrom(newKeys, middle), sliceFrom(newValues, middle))
        {
          key: right.key,
          size: count,
          height: 2,
          left: makeLeaf(sliceRange(newKeys, 0, middle), sliceRange(newValues, 0, middle)),
          right,
          keys: emptyArray(noEntries),
          values: emptyArray(noEntries),
        }
      }
    }
  } else if compare(key, node.key) < 0 {
    let oldLeft = node.left
    let newLeft = set(oldLeft, key, value, ~compare, ~max)
    // The same node back means the key already held this value: keep sharing everything.
    newLeft === oldLeft
      ? node
      : replaceLeft(node, newLeft, ~size=node.size - oldLeft.size + newLeft.size)
  } else {
    let oldRight = node.right
    let newRight = set(oldRight, key, value, ~compare, ~max)
    newRight === oldRight
      ? node
      : replaceRight(node, newRight, ~size=node.size - oldRight.size + newRight.size)
  }

// -----------------------------------------------------------------------------
// Removal
// -----------------------------------------------------------------------------

/** `node` with its first leaf replaced by `leaf`, which holds `growth` more entries. */
let rec replaceMinLeaf = (node: t<'k, 'v>, leaf: t<'k, 'v>, ~growth: int): t<'k, 'v> =>
  if node.height == 1 {
    leaf
  } else {
    {
      key: node.key,
      size: node.size + growth,
      height: node.height,
      left: replaceMinLeaf(node.left, leaf, ~growth),
      right: node.right,
      keys: node.keys,
      values: node.values,
    }
  }

/** `node` with its last leaf replaced by `leaf`, which holds `growth` more entries. */
let rec replaceMaxLeaf = (node: t<'k, 'v>, leaf: t<'k, 'v>, ~growth: int): t<'k, 'v> =>
  if node.height == 1 {
    leaf
  } else {
    {
      key: node.key,
      size: node.size + growth,
      height: node.height,
      left: node.left,
      right: replaceMaxLeaf(node.right, leaf, ~growth),
      keys: node.keys,
      values: node.values,
    }
  }

/**
What replaces `node` once a removal has left its left child as `small`, a leaf under the
minimum (possibly empty). `small` is merged with the first leaf of the right subtree, or shares
that leaf's entries; see the top of this file. The result may be one shorter than `node`.
*/
let repairLeft = (node: t<'k, 'v>, small: t<'k, 'v>, ~max: int): t<'k, 'v> => {
  let right = node.right
  let neighbour = minLeaf(right)
  let total = small.size + neighbour.size
  let keys = concat(small.keys, neighbour.keys)
  let values = concat(small.values, neighbour.values)
  if total < max {
    replaceMinLeaf(right, makeLeaf(keys, values), ~growth=small.size)
  } else {
    let leftCount = total / 2
    let newNeighbour = makeLeaf(sliceFrom(keys, leftCount), sliceFrom(values, leftCount))
    {
      key: newNeighbour.key,
      size: node.size - 1,
      height: node.height,
      left: makeLeaf(sliceRange(keys, 0, leftCount), sliceRange(values, 0, leftCount)),
      right: replaceMinLeaf(right, newNeighbour, ~growth=newNeighbour.size - neighbour.size),
      keys: node.keys,
      values: node.values,
    }
  }
}

/** `repairLeft`, for an underfull right child and the last leaf of the left subtree. */
let repairRight = (node: t<'k, 'v>, small: t<'k, 'v>, ~max: int): t<'k, 'v> => {
  let left = node.left
  let neighbour = maxLeaf(left)
  let total = small.size + neighbour.size
  let keys = concat(neighbour.keys, small.keys)
  let values = concat(neighbour.values, small.values)
  if total < max {
    replaceMaxLeaf(left, makeLeaf(keys, values), ~growth=small.size)
  } else {
    let leftCount = total - total / 2
    let newNeighbour = makeLeaf(sliceRange(keys, 0, leftCount), sliceRange(values, 0, leftCount))
    let newSmall = makeLeaf(sliceFrom(keys, leftCount), sliceFrom(values, leftCount))
    {
      key: newSmall.key,
      size: node.size - 1,
      height: node.height,
      left: replaceMaxLeaf(left, newNeighbour, ~growth=newNeighbour.size - neighbour.size),
      right: newSmall,
      keys: node.keys,
      values: node.values,
    }
  }
}

/**
`node` without `key`, or `node` itself if it doesn't hold it. If `node` is a leaf the result may
be under the minimum, or empty, for the caller to repair or discard. An internal node's result
is always a valid subtree: anything smaller than `min` that comes back from a child must be a
leaf, since an internal node holds at least two leaves' worth.
*/
let rec removeFrom = (node: t<'k, 'v>, key: 'k, ~compare: ('k, 'k) => int, ~max: int): t<'k, 'v> =>
  if node.height == 1 {
    let index = search(node.keys, key, ~compare)
    if index < 0 {
      node
    } else if node.size == 1 {
      // Not `makeLeaf`, which would read the first key of an empty array.
      {
        key: node.key,
        size: 0,
        height: 1,
        left: noChild(),
        right: noChild(),
        keys: emptyArray(noEntries),
        values: emptyArray(noEntries),
      }
    } else {
      makeLeaf(removeAt(node.keys, index), removeAt(node.values, index))
    }
  } else if compare(key, node.key) < 0 {
    let oldLeft = node.left
    let newLeft = removeFrom(oldLeft, key, ~compare, ~max)
    if newLeft === oldLeft {
      node
    } else if newLeft.size < max / 2 {
      repairLeft(node, newLeft, ~max)
    } else {
      replaceLeft(node, newLeft, ~size=node.size - 1)
    }
  } else {
    let oldRight = node.right
    let newRight = removeFrom(oldRight, key, ~compare, ~max)
    if newRight === oldRight {
      node
    } else if newRight.size < max / 2 {
      repairRight(node, newRight, ~max)
    } else {
      replaceRight(node, newRight, ~size=node.size - 1)
    }
  }

// -----------------------------------------------------------------------------
// Traversal / conversion
// -----------------------------------------------------------------------------

// These recurse down the spine and loop over each leaf. The recursion costs a call per leaf,
// not per entry, and the compiler turns the call on the right subtree into a loop.

let rec forEach = (node: t<'k, 'v>, callback: ('k, 'v) => unit): unit =>
  if node.height == 1 {
    let keys = node.keys
    let values = node.values
    for index in 0 to Array.length(keys) - 1 {
      callback(Array.getUnsafe(keys, index), Array.getUnsafe(values, index))
    }
  } else {
    forEach(node.left, callback)
    forEach(node.right, callback)
  }

let rec reduce = (node: t<'k, 'v>, initial: 'acc, callback: ('acc, 'k, 'v) => 'acc): 'acc =>
  if node.height == 1 {
    let keys = node.keys
    let values = node.values
    let accumulator = ref(initial)
    for index in 0 to Array.length(keys) - 1 {
      accumulator :=
        callback(accumulator.contents, Array.getUnsafe(keys, index), Array.getUnsafe(values, index))
    }
    accumulator.contents
  } else {
    reduce(node.right, reduce(node.left, initial, callback), callback)
  }

// The three `fill*` functions write into a result allocated at its final length; a subtree's
// entries start at `offset`.

let rec fillEntries = (node: t<'k, 'v>, result: array<('k, 'v)>, offset: int): unit =>
  if node.height == 1 {
    let keys = node.keys
    let values = node.values
    for index in 0 to Array.length(keys) - 1 {
      Array.setUnsafe(
        result,
        offset + index,
        (Array.getUnsafe(keys, index), Array.getUnsafe(values, index)),
      )
    }
  } else {
    let left = node.left
    fillEntries(left, result, offset)
    fillEntries(node.right, result, offset + left.size)
  }

let rec fillKeys = (node: t<'k, 'v>, result: array<'k>, offset: int): unit =>
  if node.height == 1 {
    let keys = node.keys
    for index in 0 to Array.length(keys) - 1 {
      Array.setUnsafe(result, offset + index, Array.getUnsafe(keys, index))
    }
  } else {
    let left = node.left
    fillKeys(left, result, offset)
    fillKeys(node.right, result, offset + left.size)
  }

let rec fillValues = (node: t<'k, 'v>, result: array<'v>, offset: int): unit =>
  if node.height == 1 {
    let values = node.values
    for index in 0 to Array.length(values) - 1 {
      Array.setUnsafe(result, offset + index, Array.getUnsafe(values, index))
    }
  } else {
    let left = node.left
    fillValues(left, result, offset)
    fillValues(node.right, result, offset + left.size)
  }

// -----------------------------------------------------------------------------
// Diagnostics
// -----------------------------------------------------------------------------

let fail = (message: string) => JsError.throwWithMessage(`ChunkNode.checkInvariants: ${message}`)

/**
Checks the subtree at `node`, whose keys must all be at least `lowerBound` and less than
`upperBound` (where given).
*/
let rec checkWithin = (
  node: t<'k, 'v>,
  ~compare: ('k, 'k) => int,
  ~max: int,
  ~isRoot: bool,
  ~lowerBound: option<'k>,
  ~upperBound: option<'k>,
): unit =>
  if node.height == 1 {
    let keys = node.keys
    let count = Array.length(keys)
    if count == 0 {
      fail("an empty leaf")
    }
    if count > max {
      fail(`a leaf of ${Int.toString(count)} entries, over the maximum of ${Int.toString(max)}`)
    }
    if !isRoot && count < max / 2 {
      fail(
        `a leaf of ${Int.toString(count)} entries, under the minimum of ${Int.toString(max / 2)}`,
      )
    }
    if Array.length(node.values) != count {
      fail("a leaf whose keys and values differ in length")
    }
    if node.size != count {
      fail(
        `a leaf's cached size ${Int.toString(node.size)} does not match its ${Int.toString(
            count,
          )} entries`,
      )
    }
    if node.key !== Array.getUnsafe(keys, 0) {
      fail("a leaf's key is not its first key")
    }
    switch lowerBound {
    | Some(bound) if compare(Array.getUnsafe(keys, 0), bound) < 0 =>
      fail("a key is less than a separator it is to the right of")
    | _ => ()
    }
    switch upperBound {
    | Some(bound) if compare(Array.getUnsafe(keys, count - 1), bound) >= 0 =>
      fail("a key is not less than a separator it is to the left of")
    | _ => ()
    }
    for index in 1 to count - 1 {
      if compare(Array.getUnsafe(keys, index - 1), Array.getUnsafe(keys, index)) >= 0 {
        fail("a leaf's keys are not in strictly ascending order")
      }
    }
  } else {
    let {left, right} = node
    if Array.length(node.keys) != 0 || Array.length(node.values) != 0 {
      fail("an internal node holds entries")
    }
    switch lowerBound {
    | Some(bound) if compare(node.key, bound) < 0 =>
      fail("a separator is less than a separator it is to the right of")
    | _ => ()
    }
    switch upperBound {
    | Some(bound) if compare(node.key, bound) >= 0 =>
      fail("a separator is not less than a separator it is to the left of")
    | _ => ()
    }
    checkWithin(left, ~compare, ~max, ~isRoot=false, ~lowerBound, ~upperBound=Some(node.key))
    checkWithin(right, ~compare, ~max, ~isRoot=false, ~lowerBound=Some(node.key), ~upperBound)
    let expectedHeight = (left.height >= right.height ? left.height : right.height) + 1
    if node.height != expectedHeight {
      fail(
        `cached height ${Int.toString(node.height)} does not match actual height ${Int.toString(
            expectedHeight,
          )}`,
      )
    }
    if left.height > right.height + 2 || right.height > left.height + 2 {
      fail(
        `unbalanced node: left height ${Int.toString(left.height)}, right height ${Int.toString(
            right.height,
          )}`,
      )
    }
    if node.size != left.size + right.size {
      fail(
        `cached size ${Int.toString(node.size)} does not match counted size ${Int.toString(
            left.size + right.size,
          )}`,
      )
    }
  }

let checkInvariants = (tree: tree<'k, 'v>, ~compare: ('k, 'k) => int, ~max: int): unit =>
  switch tree {
  | None => ()
  | Some(node) =>
    checkWithin(node, ~compare, ~max, ~isRoot=true, ~lowerBound=None, ~upperBound=None)
  }
