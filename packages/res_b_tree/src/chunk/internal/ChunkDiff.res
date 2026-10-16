// Reports where two chunked trees differ, in ascending key order, the way
// `AvlDiff.res` does for two AVL trees: a subtree that is the same object on both
// sides is skipped whole, and the pair is walked in one of two ways.
//
// - *In step* (`inStep`), while two internal nodes have the same separator. Their
//   left subtrees then cover the same range of keys, as do their right subtrees,
//   so each pair is compared by plain recursion. At two leaves that share one
//   `keys` array (which is what an overwrite leaves behind) only the values are
//   compared, with no call to the comparator.
// - *With cursors* (`walk`), for anything else: two leaves with different keys,
//   a leaf against an internal node, or two internal nodes whose separators
//   differ. Each cursor is an in-order stack of pending subtrees, plus a position
//   within the leaf on top once that leaf has been started. Two pending leaves
//   are merged as two sorted runs. Otherwise `size` decides what to open: a
//   subtree can only be identical to one of the same size, so the larger of two
//   pending subtrees is opened and the smaller kept whole. This works for any two
//   trees, whatever their shapes.
//
// Two values that are the same (`===`) are taken to be equal without asking
// `valueEqual`, just as the values inside a skipped subtree are. So `valueEqual`
// is only called for values that actually differ by reference.

type cursor<'k, 'v> = {
  // The subtrees still to be visited, next one last.
  nodes: array<ChunkNode.t<'k, 'v>>,
  mutable count: int,
  // How many entries of the subtree on top have been consumed already. Only ever
  // non-zero when that subtree is a leaf.
  mutable index: int,
}

let makeCursor = (): cursor<'k, 'v> => {nodes: [], count: 0, index: 0}

let push = (cursor: cursor<'k, 'v>, node: ChunkNode.t<'k, 'v>): unit => {
  Array.setUnsafe(cursor.nodes, cursor.count, node)
  cursor.count = cursor.count + 1
}

/** Replaces the internal node on top with its two children, left on top. */
let openSubtree = (cursor: cursor<'k, 'v>, node: ChunkNode.t<'k, 'v>): unit => {
  Array.setUnsafe(cursor.nodes, cursor.count - 1, node.right)
  Array.setUnsafe(cursor.nodes, cursor.count, node.left)
  cursor.count = cursor.count + 1
}

/** Consumes the rest of `cursor`'s tree, calling `report` for every entry left in it. */
let drainRemaining = (cursor: cursor<'k, 'v>, report: ('k, 'v) => unit): unit =>
  while cursor.count > 0 {
    cursor.count = cursor.count - 1
    let node = Array.getUnsafe(cursor.nodes, cursor.count)
    let start = cursor.index
    cursor.index = 0
    if start == 0 {
      ChunkNode.forEach(node, report)
    } else {
      let keys = node.keys
      let values = node.values
      for index in start to Array.length(keys) - 1 {
        report(Array.getUnsafe(keys, index), Array.getUnsafe(values, index))
      }
    }
  }

/** See `AvlDiff.context`. */
type context<'k, 'v> = {
  compare: ('k, 'k) => int,
  valueEqual: ('v, 'v) => bool,
  onlyLeft: ('k, 'v) => unit,
  onlyRight: ('k, 'v) => unit,
  different: ('k, 'v, 'v) => unit,
  onSharedSubtreeSkipped: unit => unit,
  // One pair of cursors serves every `walk`, each of which leaves both empty again.
  leftCursor: cursor<'k, 'v>,
  rightCursor: cursor<'k, 'v>,
}

/**
Compares the values of two leaves holding the same keys, from position `start` on. No key is
compared.
*/
let diffValues = (
  context: context<'k, 'v>,
  keys: array<'k>,
  leftValues: array<'v>,
  rightValues: array<'v>,
  start: int,
): unit =>
  if leftValues !== rightValues {
    for index in start to Array.length(keys) - 1 {
      let leftValue = Array.getUnsafe(leftValues, index)
      let rightValue = Array.getUnsafe(rightValues, index)
      if leftValue !== rightValue && !context.valueEqual(leftValue, rightValue) {
        context.different(Array.getUnsafe(keys, index), leftValue, rightValue)
      }
    }
  }

/**
Compares two different subtrees that cover the same range of keys, with cursors. Works whatever
their shapes.
*/
let walk = (
  context: context<'k, 'v>,
  leftRoot: ChunkNode.t<'k, 'v>,
  rightRoot: ChunkNode.t<'k, 'v>,
): unit => {
  let {compare, valueEqual, onlyLeft, onlyRight, different} = context
  let left = context.leftCursor
  let right = context.rightCursor
  push(left, leftRoot)
  push(right, rightRoot)
  while left.count > 0 && right.count > 0 {
    let leftNode = Array.getUnsafe(left.nodes, left.count - 1)
    let rightNode = Array.getUnsafe(right.nodes, right.count - 1)
    if leftNode === rightNode && left.index == right.index {
      context.onSharedSubtreeSkipped()
      left.count = left.count - 1
      left.index = 0
      right.count = right.count - 1
      right.index = 0
    } else if leftNode.height > 1 {
      if rightNode.height > 1 {
        // The same size but not the same node: neither can be found inside the other.
        if leftNode.size >= rightNode.size {
          openSubtree(left, leftNode)
        }
        if rightNode.size >= leftNode.size {
          openSubtree(right, rightNode)
        }
      } else {
        // An internal node is never identical to a leaf, started or not.
        openSubtree(left, leftNode)
      }
    } else if rightNode.height > 1 {
      openSubtree(right, rightNode)
    } else {
      // Two leaves: merge their keys from where each cursor stands until one runs out.
      let leftKeys = leftNode.keys
      let rightKeys = rightNode.keys
      let leftValues = leftNode.values
      let rightValues = rightNode.values
      let leftCount = Array.length(leftKeys)
      let rightCount = Array.length(rightKeys)
      let leftIndex = ref(left.index)
      let rightIndex = ref(right.index)
      if leftKeys === rightKeys && leftIndex.contents == rightIndex.contents {
        diffValues(context, leftKeys, leftValues, rightValues, leftIndex.contents)
        leftIndex := leftCount
        rightIndex := rightCount
      } else {
        while leftIndex.contents < leftCount && rightIndex.contents < rightCount {
          let leftKey = Array.getUnsafe(leftKeys, leftIndex.contents)
          let rightKey = Array.getUnsafe(rightKeys, rightIndex.contents)
          // Either side of an insertion or removal the two leaves hold the very same keys.
          let comparison = leftKey === rightKey ? 0 : compare(leftKey, rightKey)
          if comparison == 0 {
            let leftValue = Array.getUnsafe(leftValues, leftIndex.contents)
            let rightValue = Array.getUnsafe(rightValues, rightIndex.contents)
            if leftValue !== rightValue && !valueEqual(leftValue, rightValue) {
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
      }
      if leftIndex.contents >= leftCount {
        left.count = left.count - 1
        left.index = 0
      } else {
        left.index = leftIndex.contents
      }
      if rightIndex.contents >= rightCount {
        right.count = right.count - 1
        right.index = 0
      } else {
        right.index = rightIndex.contents
      }
    }
  }
  drainRemaining(left, onlyLeft)
  drainRemaining(right, onlyRight)
}

/**
Compares two subtrees that cover the same range of keys, staying in step for as long as they are
internal nodes with the same separator and handing over to `walk` where they aren't.
*/
let rec inStep = (
  context: context<'k, 'v>,
  left: ChunkNode.t<'k, 'v>,
  right: ChunkNode.t<'k, 'v>,
): unit =>
  if left === right {
    context.onSharedSubtreeSkipped()
  } else if left.height == 1 || right.height == 1 {
    if left.keys === right.keys && left.height == right.height {
      diffValues(context, left.keys, left.values, right.values, 0)
    } else {
      walk(context, left, right)
    }
  } else if left.key === right.key || context.compare(left.key, right.key) == 0 {
    inStep(context, left.left, right.left)
    inStep(context, left.right, right.right)
  } else {
    walk(context, left, right)
  }

let run = (
  left: ChunkNode.tree<'k, 'v>,
  right: ChunkNode.tree<'k, 'v>,
  ~compare: ('k, 'k) => int,
  ~valueEqual: ('v, 'v) => bool,
  ~onlyLeft: ('k, 'v) => unit,
  ~onlyRight: ('k, 'v) => unit,
  ~different: ('k, 'v, 'v) => unit,
  ~onSharedSubtreeSkipped: unit => unit,
): unit =>
  switch (left, right) {
  | (None, None) => ()
  | (None, Some(rightNode)) => ChunkNode.forEach(rightNode, onlyRight)
  | (Some(leftNode), None) => ChunkNode.forEach(leftNode, onlyLeft)
  | (Some(leftNode), Some(rightNode)) =>
    inStep(
      {
        compare,
        valueEqual,
        onlyLeft,
        onlyRight,
        different,
        onSharedSubtreeSkipped,
        leftCursor: makeCursor(),
        rightCursor: makeCursor(),
      },
      leftNode,
      rightNode,
    )
  }

let sharedSubtreeCount = (
  left: ChunkNode.tree<'k, 'v>,
  right: ChunkNode.tree<'k, 'v>,
  ~compare: ('k, 'k) => int,
): int => {
  let count = ref(0)
  run(
    left,
    right,
    ~compare,
    ~valueEqual=(_, _) => true,
    ~onlyLeft=(_, _) => (),
    ~onlyRight=(_, _) => (),
    ~different=(_, _, _) => (),
    ~onSharedSubtreeSkipped=() => count := count.contents + 1,
  )
  count.contents
}
