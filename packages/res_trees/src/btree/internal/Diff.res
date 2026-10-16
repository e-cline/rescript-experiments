/***
Reports where two `Node` trees differ, in ascending key order, without looking inside
anything they share. A port of `AvlDiff`'s two ways of walking a pair of trees to wide nodes.

*In step* (`inStep`), for two subtrees known to cover the same range of keys:

- the same node on both sides: skipped whole;
- two leaves with the same `keys` array: an overwrite reuses `keys`, so these hold the same keys,
  and only their values are compared, pairwise, with no comparator calls;
- two other leaves: their two sorted runs are merged;
- two internal nodes with the same `keys` array (the same separators): their children then cover
  the same ranges pairwise, so each pair is compared on its own, by recursion;
- anything else: handed to the cursors.

Trees derived from one another mostly stay in step: `keys` only changes in a leaf that gained or
lost a key, and in an internal node directly above a split, borrow or merge.

*With cursors* (`walk`), for two subtrees of any shape, including different heights. An in-order
cursor over each, and the question of which to open when both stand before a whole subtree. Height
settles it: a subtree can only be the same node as one of the same height, so the taller of the
two is opened, and both if they are level. Two cursors inside leaves merge them in a tight loop
of their own, unless they are at the same place in leaves with the same `keys` array, which are
finished at once (with no work at all if it is the same leaf: a cursor has to open a shared leaf
to compare its first key against a last few entries left over on the other side, and this is what
keeps that from costing a leaf's worth of comparisons). Nothing is allocated per entry or per
node: a cursor is a stack held in two parallel arrays that are reused for the whole diff.

A cursor only ever skips a subtree when the other cursor is skipping the very same node, having
already consumed everything before it. Both then stand at the same key, with their stacks intact,
so whatever follows a run of shared nodes is still compared (dropping it is a known bug in a
published B-tree diff). When one cursor runs out, `drain` reports everything left in the other,
including the unvisited siblings at every level of its stack.
*/

open Node

/**
A position in an in-order walk of one tree: the nodes from the root down to the one being
visited, each with the index of its next child (an internal node) or entry (a leaf) still to be
visited. Every node on the stack has something left to visit (`moveTo` sees to that).
*/
type cursor<'k, 'v> = {
  nodes: array<t<'k, 'v>>,
  indices: array<int>,
  mutable count: int,
  // The height of the node on top (0 for a leaf), which is one more than that of the subtree the
  // cursor stands before.
  mutable height: int,
}

let makeCursor = (): cursor<'k, 'v> => {nodes: [], indices: [], count: 0, height: 0}

let topNode = (cursor: cursor<'k, 'v>): t<'k, 'v> => Array.getUnsafe(cursor.nodes, cursor.count - 1)

let topIndex = (cursor: cursor<'k, 'v>): int => Array.getUnsafe(cursor.indices, cursor.count - 1)

let push = (cursor: cursor<'k, 'v>, node: t<'k, 'v>): unit => {
  Array.setUnsafe(cursor.nodes, cursor.count, node)
  Array.setUnsafe(cursor.indices, cursor.count, 0)
  cursor.count = cursor.count + 1
}

/**
Moves the top of the stack on to `index`, then pops every node on top that has nothing left to
visit.
*/
let moveTo = (cursor: cursor<'k, 'v>, index: int): unit => {
  Array.setUnsafe(cursor.indices, cursor.count - 1, index)
  while cursor.count > 0 && topIndex(cursor) >= width(topNode(cursor)) {
    cursor.count = cursor.count - 1
    cursor.height = cursor.height + 1
  }
}

/** Steps into the subtree the cursor stands before. The node on top must be an internal node. */
let openSubtree = (cursor: cursor<'k, 'v>): unit => {
  let node = topNode(cursor)
  let index = topIndex(cursor)
  // The parent is left pointing past the child, so that popping the child resumes after it.
  Array.setUnsafe(cursor.indices, cursor.count - 1, index + 1)
  push(cursor, childAt(node.links, index))
  cursor.height = cursor.height - 1
}

/**
Stands the (empty) cursor before `root` as a whole, by putting it under a stand-in parent, so that
`root` itself can be matched against a subtree on the other side.
*/
let start = (cursor: cursor<'k, 'v>, root: t<'k, 'v>): unit => {
  push(cursor, internal(emptyOf(sharedEmpty), [Child(root), Count(size(root))]))
  cursor.height = height(root, 0) + 1
}

/** Consumes the rest of the cursor's tree, calling `report` for every entry left in it. */
let drain = (cursor: cursor<'k, 'v>, report: ('k, 'v) => unit): unit =>
  while cursor.count > 0 {
    let node = topNode(cursor)
    let index = topIndex(cursor)
    if isLeaf(node) {
      let {keys, values} = node
      for entry in index to Array.length(keys) - 1 {
        report(Array.getUnsafe(keys, entry), Array.getUnsafe(values, entry))
      }
    } else {
      let links = node.links
      for child in index to childCount(links) - 1 {
        forEach(childAt(links, child), report)
      }
    }
    cursor.count = cursor.count - 1
  }

/**
Everything one diff needs, bundled so that the functions below can be ordinary top-level
functions taking one argument for all of it.
*/
type context<'k, 'v> = {
  compare: ('k, 'k) => int,
  valueEqual: ('v, 'v) => bool,
  onlyLeft: ('k, 'v) => unit,
  onlyRight: ('k, 'v) => unit,
  different: ('k, 'v, 'v) => unit,
  // How many subtrees have been found to be the same node on both sides, and skipped. A count
  // kept here rather than a callback: a diff a few edits apart does little else but skip shared
  // subtrees, several to a node, and a call for each (even to a function that does nothing) was a
  // good part of its time.
  mutable sharedSubtrees: int,
  // One pair of cursors serves every `walk`: each runs both to the end, leaving them empty. They
  // are made by the first `walk`, so that a diff that stays in step throughout allocates nothing
  // but this record.
  mutable cursors: option<(cursor<'k, 'v>, cursor<'k, 'v>)>,
}

/** Compares two leaves that share their `keys` array, from index `from` onwards: values only. */
let compareValues = (
  context: context<'k, 'v>,
  left: t<'k, 'v>,
  right: t<'k, 'v>,
  from: int,
): unit => {
  let {valueEqual, different} = context
  let keys = left.keys
  let leftValues = left.values
  let rightValues = right.values
  for index in from to Array.length(keys) - 1 {
    let leftValue = Array.getUnsafe(leftValues, index)
    let rightValue = Array.getUnsafe(rightValues, index)

    // Nearly every pair is the very same value, untouched since the two leaves were one. Those
    // are passed over without a call: any `valueEqual` holds a value equal to itself.
    if leftValue !== rightValue && !valueEqual(leftValue, rightValue) {
      different(Array.getUnsafe(keys, index), leftValue, rightValue)
    }
  }
}

/** Compares two leaves that cover the same range of keys, by merging their sorted runs. */
let mergeLeaves = (context: context<'k, 'v>, left: t<'k, 'v>, right: t<'k, 'v>): unit => {
  let {compare, valueEqual, onlyLeft, onlyRight, different} = context
  let leftKeys = left.keys
  let leftValues = left.values
  let rightKeys = right.keys
  let rightValues = right.values
  let leftCount = Array.length(leftKeys)
  let rightCount = Array.length(rightKeys)
  let leftIndex = ref(0)
  let rightIndex = ref(0)
  while leftIndex.contents < leftCount && rightIndex.contents < rightCount {
    let leftKey = Array.getUnsafe(leftKeys, leftIndex.contents)
    let rightKey = Array.getUnsafe(rightKeys, rightIndex.contents)
    let comparison = compare(leftKey, rightKey)
    if comparison == 0 {
      let leftValue = Array.getUnsafe(leftValues, leftIndex.contents)
      let rightValue = Array.getUnsafe(rightValues, rightIndex.contents)
      if !valueEqual(leftValue, rightValue) {
        different(leftKey, leftValue, rightValue)
      }
      leftIndex := leftIndex.contents + 1
      rightIndex := rightIndex.contents + 1
    } else if comparison < 0 {
      onlyLeft(leftKey, Array.getUnsafe(leftValues, leftIndex.contents))
      leftIndex := leftIndex.contents + 1
    } else {
      onlyRight(rightKey, Array.getUnsafe(rightValues, rightIndex.contents))
      rightIndex := rightIndex.contents + 1
    }
  }
  for index in leftIndex.contents to leftCount - 1 {
    onlyLeft(Array.getUnsafe(leftKeys, index), Array.getUnsafe(leftValues, index))
  }
  for index in rightIndex.contents to rightCount - 1 {
    onlyRight(Array.getUnsafe(rightKeys, index), Array.getUnsafe(rightValues, index))
  }
}

/**
Compares two different subtrees that cover the same range of keys, with cursors. Works whatever
their shapes and heights.
*/
let walk = (context: context<'k, 'v>, leftRoot: t<'k, 'v>, rightRoot: t<'k, 'v>): unit => {
  let {compare, valueEqual, onlyLeft, onlyRight, different} = context
  let (left, right) = switch context.cursors {
  | Some(cursors) => cursors
  | None =>
    let cursors = (makeCursor(), makeCursor())
    context.cursors = Some(cursors)
    cursors
  }
  start(left, leftRoot)
  start(right, rightRoot)
  while left.count > 0 && right.count > 0 {
    let leftNode = topNode(left)
    let rightNode = topNode(right)
    if isLeaf(leftNode) {
      if isLeaf(rightNode) {
        let leftKeys = leftNode.keys
        let rightKeys = rightNode.keys
        let leftCount = Array.length(leftKeys)
        let rightCount = Array.length(rightKeys)
        let leftStart = topIndex(left)
        let rightStart = topIndex(right)
        if leftKeys === rightKeys && leftStart == rightStart {
          // Both cursors are at the same place in leaves holding the same keys, so what is left
          // of the two can be finished here. It is commonly the very same leaf, which one cursor
          // had to open to compare its first key with the other's last few entries: nothing in
          // it needs looking at.
          if leftNode !== rightNode {
            compareValues(context, leftNode, rightNode, leftStart)
          } else if leftStart == 0 {
            context.sharedSubtrees = context.sharedSubtrees + 1
          }
          moveTo(left, leftCount)
          moveTo(right, rightCount)
        } else {
          // Both cursors are inside leaves: merge the two runs for as long as both last. This is
          // `mergeLeaves`, except that either leaf may have been entered part-way through and
          // either may outlast the other.
          let leftValues = leftNode.values
          let rightValues = rightNode.values
          let leftIndex = ref(leftStart)
          let rightIndex = ref(rightStart)
          while leftIndex.contents < leftCount && rightIndex.contents < rightCount {
            let leftKey = Array.getUnsafe(leftKeys, leftIndex.contents)
            let rightKey = Array.getUnsafe(rightKeys, rightIndex.contents)
            let comparison = compare(leftKey, rightKey)
            if comparison == 0 {
              let leftValue = Array.getUnsafe(leftValues, leftIndex.contents)
              let rightValue = Array.getUnsafe(rightValues, rightIndex.contents)
              if !valueEqual(leftValue, rightValue) {
                different(leftKey, leftValue, rightValue)
              }
              leftIndex := leftIndex.contents + 1
              rightIndex := rightIndex.contents + 1
            } else if comparison < 0 {
              onlyLeft(leftKey, Array.getUnsafe(leftValues, leftIndex.contents))
              leftIndex := leftIndex.contents + 1
            } else {
              onlyRight(rightKey, Array.getUnsafe(rightValues, rightIndex.contents))
              rightIndex := rightIndex.contents + 1
            }
          }
          moveTo(left, leftIndex.contents)
          moveTo(right, rightIndex.contents)
        }
      } else {
        // An entry against a subtree: look inside the subtree.
        openSubtree(right)
      }
    } else if isLeaf(rightNode) {
      openSubtree(left)
    } else {
      let leftIndex = topIndex(left)
      let rightIndex = topIndex(right)
      let leftChild = childAt(leftNode.links, leftIndex)
      let rightChild = childAt(rightNode.links, rightIndex)
      if leftChild === rightChild {
        context.sharedSubtrees = context.sharedSubtrees + 1
        moveTo(left, leftIndex + 1)
        moveTo(right, rightIndex + 1)
      } else if left.height > right.height {
        openSubtree(left)
      } else if left.height < right.height {
        openSubtree(right)
      } else if leftChild.keys === rightChild.keys && isLeaf(leftChild) {
        // Two leaves holding exactly the same keys, with everything before them consumed on both
        // sides.
        compareValues(context, leftChild, rightChild, 0)
        moveTo(left, leftIndex + 1)
        moveTo(right, rightIndex + 1)
      } else {
        // Level, but not the same node: neither can be found inside the other.
        openSubtree(left)
        openSubtree(right)
      }
    }
  }
  drain(left, onlyLeft)
  drain(right, onlyRight)
}

/**
Compares two subtrees that cover the same range of keys, staying in step for as long as they are
built around the same `keys` arrays and handing over to `walk` where they aren't.
*/
let rec inStep = (context: context<'k, 'v>, left: t<'k, 'v>, right: t<'k, 'v>): unit =>
  if left === right {
    context.sharedSubtrees = context.sharedSubtrees + 1
  } else if isLeaf(left) && isLeaf(right) {
    if left.keys === right.keys {
      compareValues(context, left, right, 0)
    } else {
      mergeLeaves(context, left, right)
    }
  } else if left.keys === right.keys && !isLeaf(left) && !isLeaf(right) {
    let leftLinks = left.links
    let rightLinks = right.links
    for index in 0 to childCount(leftLinks) - 1 {
      let leftChild = childAt(leftLinks, index)
      let rightChild = childAt(rightLinks, index)

      // Checked here as well as on entry, to spare a call for each of the many children that are
      // shared.
      if leftChild === rightChild {
        context.sharedSubtrees = context.sharedSubtrees + 1
      } else {
        inStep(context, leftChild, rightChild)
      }
    }
  } else {
    walk(context, left, right)
  }

/**
Reports the differences between two trees through the callbacks, in ascending key order, and
returns how many subtrees it skipped for being the same node in both.
*/
let run = (
  left: option<t<'k, 'v>>,
  right: option<t<'k, 'v>>,
  ~compare: ('k, 'k) => int,
  ~valueEqual: ('v, 'v) => bool,
  ~onlyLeft: ('k, 'v) => unit,
  ~onlyRight: ('k, 'v) => unit,
  ~different: ('k, 'v, 'v) => unit,
): int =>
  switch (left, right) {
  | (None, None) => 0
  | (None, Some(rightNode)) =>
    forEach(rightNode, onlyRight)
    0
  | (Some(leftNode), None) =>
    forEach(leftNode, onlyLeft)
    0
  | (Some(leftNode), Some(rightNode)) =>
    let context = {
      compare,
      valueEqual,
      onlyLeft,
      onlyRight,
      different,
      sharedSubtrees: 0,
      cursors: None,
    }

    // `inStep` would reach the same `walk` and `mergeLeaves` calls by itself. Making them here as
    // well gives each a second caller, which keeps it a function of its own in the minified
    // output (see "Single callers" in `BTree`, and the same note in `AvlDiff.run`).
    if leftNode === rightNode || leftNode.keys === rightNode.keys {
      inStep(context, leftNode, rightNode)
    } else if isLeaf(leftNode) {
      if isLeaf(rightNode) {
        mergeLeaves(context, leftNode, rightNode)
      } else {
        walk(context, leftNode, rightNode)
      }
    } else {
      walk(context, leftNode, rightNode)
    }
    context.sharedSubtrees
  }
