// See `AvlNode.resi` for the node shape and its invariants. The balancing code
// (`create`, `balance`, and the shape of `set`/`remove`) follows
// `Belt_internalAVLtree`/`Belt_MapDict` closely, with `size` maintained
// alongside `height`.

type rec t<'k, 'v> = {
  key: 'k,
  value: 'v,
  height: int,
  size: int,
  left: option<t<'k, 'v>>,
  right: option<t<'k, 'v>>,
}

type tree<'k, 'v> = option<t<'k, 'v>>

let height = (tree: tree<'k, 'v>): int =>
  switch tree {
  | None => 0
  | Some(node) => node.height
  }

let size = (tree: tree<'k, 'v>): int =>
  switch tree {
  | None => 0
  | Some(node) => node.size
  }

// -----------------------------------------------------------------------------
// Construction and balancing
// -----------------------------------------------------------------------------

let singleton = (key: 'k, value: 'v): t<'k, 'v> => {
  key,
  value,
  height: 1,
  size: 1,
  left: None,
  right: None,
}

/** A node over two subtrees already known to be balanced against each other. */
let create = (left: tree<'k, 'v>, key: 'k, value: 'v, right: tree<'k, 'v>): t<'k, 'v> => {
  let leftHeight = height(left)
  let rightHeight = height(right)
  {
    key,
    value,
    height: (leftHeight >= rightHeight ? leftHeight : rightHeight) + 1,
    size: size(left) + size(right) + 1,
    left,
    right,
  }
}

/**
A node over two subtrees whose heights may differ by up to 3 -- what a single insertion or
removal below a balanced node can leave behind -- rotating if they differ by more than 2.
`size` is the number of entries the result will hold, which every caller already knows.
*/
let balance = (left: tree<'k, 'v>, key: 'k, value: 'v, right: tree<'k, 'v>, ~size: int): t<
  'k,
  'v,
> => {
  let leftHeight = height(left)
  let rightHeight = height(right)
  if leftHeight > rightHeight + 2 {
    // `left` is at least 3 tall, so it can't be empty.
    let leftNode = Option.getUnsafe(left)
    if height(leftNode.left) >= height(leftNode.right) {
      create(
        leftNode.left,
        leftNode.key,
        leftNode.value,
        Some(create(leftNode.right, key, value, right)),
      )
    } else {
      // `leftNode.right` is the taller of its children, so it can't be empty either.
      let pivot = Option.getUnsafe(leftNode.right)
      create(
        Some(create(leftNode.left, leftNode.key, leftNode.value, pivot.left)),
        pivot.key,
        pivot.value,
        Some(create(pivot.right, key, value, right)),
      )
    }
  } else if rightHeight > leftHeight + 2 {
    let rightNode = Option.getUnsafe(right)
    if height(rightNode.right) >= height(rightNode.left) {
      create(
        Some(create(left, key, value, rightNode.left)),
        rightNode.key,
        rightNode.value,
        rightNode.right,
      )
    } else {
      let pivot = Option.getUnsafe(rightNode.left)
      create(
        Some(create(left, key, value, pivot.left)),
        pivot.key,
        pivot.value,
        Some(create(pivot.right, rightNode.key, rightNode.value, rightNode.right)),
      )
    }
  } else {
    {
      key,
      value,
      height: (leftHeight >= rightHeight ? leftHeight : rightHeight) + 1,
      size,
      left,
      right,
    }
  }
}

/**
`node` with its left subtree replaced by `newLeft`, which must be one insertion, removal or
overwrite away from the old one.

`size` is the new node's size, which the caller knows more cheaply than it could be recounted.

Most of the nodes on the path of an edit sit above the point where the tree stopped changing
height. For those, the new node's height is the old node's, so nothing is recomputed and
`node.right` is never looked at. Only where the replaced subtree's height did change is
`balance` needed.
*/
let replaceLeft = (node: t<'k, 'v>, newLeft: tree<'k, 'v>, ~size: int): t<'k, 'v> => {
  let oldLeft = node.left
  if height(newLeft) == height(oldLeft) {
    {
      key: node.key,
      value: node.value,
      height: node.height,
      size,
      left: newLeft,
      right: node.right,
    }
  } else {
    balance(newLeft, node.key, node.value, node.right, ~size)
  }
}

/** `replaceLeft`, for the right subtree. */
let replaceRight = (node: t<'k, 'v>, newRight: tree<'k, 'v>, ~size: int): t<'k, 'v> => {
  let oldRight = node.right
  if height(newRight) == height(oldRight) {
    {
      key: node.key,
      value: node.value,
      height: node.height,
      size,
      left: node.left,
      right: newRight,
    }
  } else {
    balance(node.left, node.key, node.value, newRight, ~size)
  }
}

let rec buildBalanced = (entries: array<('k, 'v)>, start: int, end: int): tree<'k, 'v> =>
  if start >= end {
    None
  } else {
    let middle = start + (end - start) / 2
    let (key, value) = Array.getUnsafe(entries, middle)
    Some(
      create(
        buildBalanced(entries, start, middle),
        key,
        value,
        buildBalanced(entries, middle + 1, end),
      ),
    )
  }

let fromSortedArray = (entries: array<('k, 'v)>): tree<'k, 'v> =>
  buildBalanced(entries, 0, Array.length(entries))

// -----------------------------------------------------------------------------
// Lookup
// -----------------------------------------------------------------------------

let rec get = (tree: tree<'k, 'v>, key: 'k, ~compare: ('k, 'k) => int): option<'v> =>
  switch tree {
  | None => None
  | Some(node) =>
    let comparison = compare(key, node.key)
    if comparison == 0 {
      Some(node.value)
    } else {
      get(comparison < 0 ? node.left : node.right, key, ~compare)
    }
  }

let rec has = (tree: tree<'k, 'v>, key: 'k, ~compare: ('k, 'k) => int): bool =>
  switch tree {
  | None => false
  | Some(node) =>
    let comparison = compare(key, node.key)
    comparison == 0 || has(comparison < 0 ? node.left : node.right, key, ~compare)
  }

let rec minNode = (node: t<'k, 'v>): t<'k, 'v> =>
  switch node.left {
  | None => node
  | Some(left) => minNode(left)
  }

let minKey = (node: t<'k, 'v>): 'k => minNode(node).key

let rec maxKey = (node: t<'k, 'v>): 'k =>
  switch node.right {
  | None => node.key
  | Some(right) => maxKey(right)
  }

// -----------------------------------------------------------------------------
// Order statistics
// -----------------------------------------------------------------------------

let rec getAt = (node: t<'k, 'v>, index: int): ('k, 'v) => {
  let leftSize = size(node.left)
  if index == leftSize {
    (node.key, node.value)
  } else if index < leftSize {
    // In range, so `left` holds more than `index` entries and can't be empty.
    getAt(Option.getUnsafe(node.left), index)
  } else {
    getAt(Option.getUnsafe(node.right), index - leftSize - 1)
  }
}

/** `skipped` is the number of entries already known to sort before everything in `tree`. */
let rec indexOfFrom = (
  tree: tree<'k, 'v>,
  key: 'k,
  skipped: int,
  ~compare: ('k, 'k) => int,
): option<int> =>
  switch tree {
  | None => None
  | Some(node) =>
    let comparison = compare(key, node.key)
    if comparison == 0 {
      Some(skipped + size(node.left))
    } else if comparison < 0 {
      indexOfFrom(node.left, key, skipped, ~compare)
    } else {
      indexOfFrom(node.right, key, skipped + size(node.left) + 1, ~compare)
    }
  }

let indexOf = (tree: tree<'k, 'v>, key: 'k, ~compare: ('k, 'k) => int): option<int> =>
  indexOfFrom(tree, key, 0, ~compare)

// -----------------------------------------------------------------------------
// Insertion and removal
// -----------------------------------------------------------------------------

let rec set = (tree: tree<'k, 'v>, key: 'k, value: 'v, ~compare: ('k, 'k) => int): t<'k, 'v> =>
  switch tree {
  | None => singleton(key, value)
  | Some(node) =>
    let comparison = compare(key, node.key)
    if comparison == 0 {
      node.value === value ? node : {...node, value}
    } else if comparison < 0 {
      let newLeft = set(node.left, key, value, ~compare)
      // The same node back means the key already held this value: keep sharing everything.
      switch node.left {
      | Some(oldLeft) if oldLeft === newLeft => node
      | oldLeft => replaceLeft(node, Some(newLeft), ~size=node.size - size(oldLeft) + newLeft.size)
      }
    } else {
      let newRight = set(node.right, key, value, ~compare)
      switch node.right {
      | Some(oldRight) if oldRight === newRight => node
      | oldRight =>
        replaceRight(node, Some(newRight), ~size=node.size - size(oldRight) + newRight.size)
      }
    }
  }

/** `node` without its smallest entry. */
let rec removeMin = (node: t<'k, 'v>): tree<'k, 'v> =>
  switch node.left {
  | None => node.right
  | Some(left) => Some(replaceLeft(node, removeMin(left), ~size=node.size - 1))
  }

let rec removeFrom = (node: t<'k, 'v>, key: 'k, ~compare: ('k, 'k) => int): tree<'k, 'v> => {
  let comparison = compare(key, node.key)
  if comparison == 0 {
    switch node.right {
    | None => node.left
    | Some(right) =>
      switch node.left {
      | None => node.right
      | Some(_) =>
        // Two children: the right subtree's smallest entry takes this node's place.
        let successor = minNode(right)
        let newRight = removeMin(right)
        if height(newRight) == right.height {
          // As in `replaceRight`: nothing above here changes height, and the size drops by one.
          Some({
            key: successor.key,
            value: successor.value,
            height: node.height,
            size: node.size - 1,
            left: node.left,
            right: newRight,
          })
        } else {
          Some(balance(node.left, successor.key, successor.value, newRight, ~size=node.size - 1))
        }
      }
    }
  } else if comparison < 0 {
    switch node.left {
    | None => Some(node)
    | Some(left) =>
      let newLeft = removeFrom(left, key, ~compare)
      newLeft === node.left ? Some(node) : Some(replaceLeft(node, newLeft, ~size=node.size - 1))
    }
  } else {
    switch node.right {
    | None => Some(node)
    | Some(right) =>
      let newRight = removeFrom(right, key, ~compare)
      newRight === node.right ? Some(node) : Some(replaceRight(node, newRight, ~size=node.size - 1))
    }
  }
}

let remove = (tree: tree<'k, 'v>, key: 'k, ~compare: ('k, 'k) => int): tree<'k, 'v> =>
  switch tree {
  | None => None
  | Some(node) => removeFrom(node, key, ~compare)
  }

// -----------------------------------------------------------------------------
// Traversal / conversion
// -----------------------------------------------------------------------------

// `forEach` and `reduce` keep their own stack of the nodes whose left subtrees they are
// inside, rather than recursing: one loop making one call per entry (the callback) measured
// 10-15% faster than a recursive function making two.

let forEachNode = (root: t<'k, 'v>, callback: ('k, 'v) => unit): unit => {
  let stack = []
  let depth = ref(0)
  let current = ref(Some(root))
  while current.contents !== None || depth.contents > 0 {
    switch current.contents {
    | Some(node) =>
      Array.setUnsafe(stack, depth.contents, node)
      depth := depth.contents + 1
      current := node.left
    | None =>
      depth := depth.contents - 1
      let node = Array.getUnsafe(stack, depth.contents)
      callback(node.key, node.value)
      current := node.right
    }
  }
}

let forEach = (tree: tree<'k, 'v>, callback: ('k, 'v) => unit): unit =>
  switch tree {
  | None => ()
  | Some(node) => forEachNode(node, callback)
  }

let reduce = (tree: tree<'k, 'v>, initial: 'acc, callback: ('acc, 'k, 'v) => 'acc): 'acc => {
  let accumulator = ref(initial)
  let stack = []
  let depth = ref(0)
  let current = ref(tree)
  while current.contents !== None || depth.contents > 0 {
    switch current.contents {
    | Some(node) =>
      Array.setUnsafe(stack, depth.contents, node)
      depth := depth.contents + 1
      current := node.left
    | None =>
      depth := depth.contents - 1
      let node = Array.getUnsafe(stack, depth.contents)
      accumulator := callback(accumulator.contents, node.key, node.value)
      current := node.right
    }
  }
  accumulator.contents
}

// The three `fill*` functions write straight into a result array allocated at its final
// length: a node's own position is `offset` plus the size of its left subtree, so nothing
// needs to be threaded back out of the recursion. They recurse, checking each child before
// descending rather than recursing into `None`; an explicit stack measured no faster here,
// where there is no callback to call.

let rec fillEntries = (node: t<'k, 'v>, result: array<('k, 'v)>, offset: int): unit => {
  let position = switch node.left {
  | None => offset
  | Some(left) =>
    fillEntries(left, result, offset)
    offset + left.size
  }
  Array.setUnsafe(result, position, (node.key, node.value))
  switch node.right {
  | None => ()
  | Some(right) => fillEntries(right, result, position + 1)
  }
}

let rec fillKeys = (node: t<'k, 'v>, result: array<'k>, offset: int): unit => {
  let position = switch node.left {
  | None => offset
  | Some(left) =>
    fillKeys(left, result, offset)
    offset + left.size
  }
  Array.setUnsafe(result, position, node.key)
  switch node.right {
  | None => ()
  | Some(right) => fillKeys(right, result, position + 1)
  }
}

let rec fillValues = (node: t<'k, 'v>, result: array<'v>, offset: int): unit => {
  let position = switch node.left {
  | None => offset
  | Some(left) =>
    fillValues(left, result, offset)
    offset + left.size
  }
  Array.setUnsafe(result, position, node.value)
  switch node.right {
  | None => ()
  | Some(right) => fillValues(right, result, position + 1)
  }
}

let toArray = (tree: tree<'k, 'v>): array<('k, 'v)> => {
  switch tree {
  | None => []
  | Some(node) =>
    let result = Belt.Array.makeUninitializedUnsafe(node.size)
    fillEntries(node, result, 0)
    result
  }
}

let keysArray = (tree: tree<'k, 'v>): array<'k> => {
  switch tree {
  | None => []
  | Some(node) =>
    let result = Belt.Array.makeUninitializedUnsafe(node.size)
    fillKeys(node, result, 0)
    result
  }
}

let valuesArray = (tree: tree<'k, 'v>): array<'v> => {
  switch tree {
  | None => []
  | Some(node) =>
    let result = Belt.Array.makeUninitializedUnsafe(node.size)
    fillValues(node, result, 0)
    result
  }
}

// -----------------------------------------------------------------------------
// Diagnostics
// -----------------------------------------------------------------------------

let fail = (message: string) => JsError.throwWithMessage(`AvlNode.checkInvariants: ${message}`)

/**
Checks the subtree at `tree`, whose keys must all lie strictly between `lowerBound` and
`upperBound` (where given).
*/
let rec checkWithin = (
  tree: tree<'k, 'v>,
  ~compare: ('k, 'k) => int,
  ~lowerBound: option<'k>,
  ~upperBound: option<'k>,
): unit =>
  switch tree {
  | None => ()
  | Some(node) =>
    switch lowerBound {
    | Some(bound) if compare(node.key, bound) <= 0 =>
      fail("a key is not greater than an ancestor it is to the right of")
    | _ => ()
    }
    switch upperBound {
    | Some(bound) if compare(node.key, bound) >= 0 =>
      fail("a key is not less than an ancestor it is to the left of")
    | _ => ()
    }
    checkWithin(node.left, ~compare, ~lowerBound, ~upperBound=Some(node.key))
    checkWithin(node.right, ~compare, ~lowerBound=Some(node.key), ~upperBound)

    let leftHeight = height(node.left)
    let rightHeight = height(node.right)
    let expectedHeight = max(leftHeight, rightHeight) + 1
    if node.height != expectedHeight {
      fail(
        `cached height ${Int.toString(node.height)} does not match actual height ${Int.toString(
            expectedHeight,
          )}`,
      )
    }
    if leftHeight > rightHeight + 2 || rightHeight > leftHeight + 2 {
      fail(
        `unbalanced node: left height ${Int.toString(leftHeight)}, right height ${Int.toString(
            rightHeight,
          )}`,
      )
    }
    let expectedSize = size(node.left) + size(node.right) + 1
    if node.size != expectedSize {
      fail(
        `cached size ${Int.toString(node.size)} does not match counted size ${Int.toString(
            expectedSize,
          )}`,
      )
    }
  }

let checkInvariants = (tree: tree<'k, 'v>, ~compare: ('k, 'k) => int): unit =>
  checkWithin(tree, ~compare, ~lowerBound=None, ~upperBound=None)
