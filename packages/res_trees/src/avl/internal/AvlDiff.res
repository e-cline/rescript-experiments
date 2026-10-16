// Reports where two trees differ, in ascending key order, without looking inside
// anything they share: a subtree that is the exact same node on both sides
// (`===`) is skipped whole. `AvlNode.set`/`remove` only rebuild the path from the
// root to whatever changed (plus the few nodes a rotation touches), so every
// subtree off that path is shared, and diffing two trees a handful of edits apart
// costs roughly O(edits * height) rather than O(size).
//
// There are two ways of walking the pair, the same two that Jane Street's
// `Base.Map.fold_symmetric_diff` (which `Incr_map` is built on) uses:
//
// - *In step* (`inStep`), while the two subtrees being compared have the same
//   key at their roots. Their left subtrees then cover exactly the same range of
//   keys, as do their right subtrees, so each pair can be compared on its own by
//   plain recursion, with no bookkeeping at all. Trees derived from one another
//   mostly keep this shape: an overwrite never changes it, and an insertion or
//   removal only changes it where it rotates or replaces a node's key.
// - *With cursors* (`walk`), from wherever the roots' keys differ. An in-order
//   cursor over each subtree, and the question of which to advance. A rotation
//   moves a subtree to a different depth, so the same subtree can be a whole
//   pending item on one side while still buried inside a larger one on the other.
//   Each node's `size` settles which to open: a subtree can only be identical to
//   one of the same size, so when the two pending subtrees differ in size, the
//   larger one is opened and the smaller is kept whole, to be matched against
//   whatever comes out. This handles any two trees, whatever their shapes.

/**
A position within an in-order walk of one tree: a stack of the items still to be visited,
next one on top. An item is either a whole subtree or a single node's own entry; opening a
subtree replaces it with its left subtree, its root's entry, and its right subtree.

The stack is two parallel arrays, indexed up to `count`, rather than an array of item
records, so that walking allocates nothing per node.
*/
type cursor<'k, 'v> = {
  nodes: array<AvlNode.t<'k, 'v>>,
  // Whether the item at the same index in `nodes` is that node's entry alone, rather than
  // its whole subtree.
  isEntry: array<bool>,
  mutable count: int,
}

let push = (cursor: cursor<'k, 'v>, node: AvlNode.t<'k, 'v>, isEntry: bool): unit => {
  Array.setUnsafe(cursor.nodes, cursor.count, node)
  Array.setUnsafe(cursor.isEntry, cursor.count, isEntry)
  cursor.count = cursor.count + 1
}

let makeCursor = (): cursor<'k, 'v> => {nodes: [], isEntry: [], count: 0}

let isDone = (cursor: cursor<'k, 'v>): bool => cursor.count == 0

/** The node of the item on top. The cursor must not be done. */
let topNode = (cursor: cursor<'k, 'v>): AvlNode.t<'k, 'v> =>
  Array.getUnsafe(cursor.nodes, cursor.count - 1)

/** Whether the item on top is a single entry rather than a subtree. The cursor must not be done. */
let topIsEntry = (cursor: cursor<'k, 'v>): bool => Array.getUnsafe(cursor.isEntry, cursor.count - 1)

/** Moves past the item on top, whether that is an entry just reported or a subtree being skipped. */
let advance = (cursor: cursor<'k, 'v>): unit => cursor.count = cursor.count - 1

/** Replaces the subtree on top with its parts, leftmost on top. */
let openSubtree = (cursor: cursor<'k, 'v>): unit => {
  let node = topNode(cursor)
  cursor.count = cursor.count - 1
  switch node.right {
  | None => ()
  | Some(right) => push(cursor, right, false)
  }
  push(cursor, node, true)
  switch node.left {
  | None => ()
  | Some(left) => push(cursor, left, false)
  }
}

/**
Consumes the rest of `cursor`'s tree, calling `report` for every entry left in it. Used once
the other side of a walk has run out.
*/
let drainRemaining = (cursor: cursor<'k, 'v>, report: ('k, 'v) => unit): unit =>
  while !isDone(cursor) {
    let node = topNode(cursor)
    let isEntry = topIsEntry(cursor)
    advance(cursor)
    if isEntry {
      report(node.key, node.value)
    } else {
      AvlNode.forEach(Some(node), report)
    }
  }

/**
Everything one diff needs, bundled so that the mutually recursive functions below can be
ordinary top-level functions taking one argument for all of it, rather than closures.
`onSharedSubtreeSkipped` is called once for every subtree proved identical (by reference) and
skipped.
*/
type context<'k, 'v> = {
  compare: ('k, 'k) => int,
  valueEqual: ('v, 'v) => bool,
  onlyLeft: ('k, 'v) => unit,
  onlyRight: ('k, 'v) => unit,
  different: ('k, 'v, 'v) => unit,
  onSharedSubtreeSkipped: unit => unit,
  // One pair of cursors serves every stretch that needs them: `walk` always runs to the end of
  // the two subtrees it is given before returning, leaving both cursors empty again.
  leftCursor: cursor<'k, 'v>,
  rightCursor: cursor<'k, 'v>,
}

/**
Compares two different subtrees that cover the same range of keys, with cursors. Works whatever
their shapes.
*/
let walk = (
  context: context<'k, 'v>,
  leftRoot: AvlNode.t<'k, 'v>,
  rightRoot: AvlNode.t<'k, 'v>,
): unit => {
  let {compare, valueEqual, onlyLeft, onlyRight, different, onSharedSubtreeSkipped} = context
  let left = context.leftCursor
  let right = context.rightCursor
  push(left, leftRoot, false)
  push(right, rightRoot, false)
  while !isDone(left) && !isDone(right) {
    let leftNode = topNode(left)
    let rightNode = topNode(right)
    if topIsEntry(left) {
      if topIsEntry(right) {
        let comparison = compare(leftNode.key, rightNode.key)
        if comparison == 0 {
          if !valueEqual(leftNode.value, rightNode.value) {
            different(leftNode.key, leftNode.value, rightNode.value)
          }
          advance(left)
          advance(right)
        } else if comparison < 0 {
          onlyLeft(leftNode.key, leftNode.value)
          advance(left)
        } else {
          onlyRight(rightNode.key, rightNode.value)
          advance(right)
        }
      } else {
        openSubtree(right)
      }
    } else if topIsEntry(right) {
      openSubtree(left)
    } else if leftNode === rightNode {
      onSharedSubtreeSkipped()
      advance(left)
      advance(right)
    } else if leftNode.size > rightNode.size {
      openSubtree(left)
    } else if leftNode.size < rightNode.size {
      openSubtree(right)
    } else {
      // The same size but not the same node: neither can be found inside the other.
      openSubtree(left)
      openSubtree(right)
    }
  }
  drainRemaining(left, onlyLeft)
  drainRemaining(right, onlyRight)
}

/**
Compares two possibly-empty subtrees that cover the same range of keys, staying in step for as
long as their roots have the same key and handing over to `walk` where they don't.
*/
let rec inStep = (
  context: context<'k, 'v>,
  left: AvlNode.tree<'k, 'v>,
  right: AvlNode.tree<'k, 'v>,
): unit =>
  switch (left, right) {
  | (None, None) => ()
  | (None, Some(_)) => AvlNode.forEach(right, context.onlyRight)
  | (Some(_), None) => AvlNode.forEach(left, context.onlyLeft)
  | (Some(leftNode), Some(rightNode)) =>
    if leftNode === rightNode {
      context.onSharedSubtreeSkipped()
    } else if context.compare(leftNode.key, rightNode.key) == 0 {
      inStep(context, leftNode.left, rightNode.left)
      if !context.valueEqual(leftNode.value, rightNode.value) {
        context.different(leftNode.key, leftNode.value, rightNode.value)
      }
      inStep(context, leftNode.right, rightNode.right)
    } else {
      walk(context, leftNode, rightNode)
    }
  }

let run = (
  left: AvlNode.tree<'k, 'v>,
  right: AvlNode.tree<'k, 'v>,
  ~compare: ('k, 'k) => int,
  ~valueEqual: ('v, 'v) => bool,
  ~onlyLeft: ('k, 'v) => unit,
  ~onlyRight: ('k, 'v) => unit,
  ~different: ('k, 'v, 'v) => unit,
  ~onSharedSubtreeSkipped: unit => unit,
): unit => {
  let context = {
    compare,
    valueEqual,
    onlyLeft,
    onlyRight,
    different,
    onSharedSubtreeSkipped,
    leftCursor: makeCursor(),
    rightCursor: makeCursor(),
  }
  // `inStep` would reach the same `walk` call by itself. Making it here as well keeps `walk` a
  // function of its own in the compiled output: with a single caller the compiler inlines it
  // into `inStep`, and V8 then optimizes the cursor loop poorly (a diff of two differently
  // shaped 100,000-entry trees measured about 1.6x slower that way).
  switch (left, right) {
  | (Some(leftNode), Some(rightNode))
    if leftNode !== rightNode && compare(leftNode.key, rightNode.key) != 0 =>
    walk(context, leftNode, rightNode)
  | _ => inStep(context, left, right)
  }
}

let diff = (
  left: AvlNode.tree<'k, 'v>,
  right: AvlNode.tree<'k, 'v>,
  ~compare: ('k, 'k) => int,
  ~valueEqual: ('v, 'v) => bool,
  ~onlyLeft: ('k, 'v) => unit,
  ~onlyRight: ('k, 'v) => unit,
  ~different: ('k, 'v, 'v) => unit,
): unit =>
  run(
    left,
    right,
    ~compare,
    ~valueEqual,
    ~onlyLeft,
    ~onlyRight,
    ~different,
    ~onSharedSubtreeSkipped=() => (),
  )

let sharedSubtreeCount = (
  left: AvlNode.tree<'k, 'v>,
  right: AvlNode.tree<'k, 'v>,
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
