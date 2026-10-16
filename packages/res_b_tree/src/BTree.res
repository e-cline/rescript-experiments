// A thin facade over `internal/` (`Node`, `Insert`, `Delete`, `Diff`, `ArrayOps`); see
// `BTree.resi` for what this module promises, and `Node.res` for the node layout.
//
// ## Single callers
//
// The benchmarks, like a consumer's production build, run this code bundled and minified, and the
// minifier inlines a function that has a single caller: where the body has a loop or an early
// return, as a function expression called on the spot. V8 was then seen to allocate a closure on
// every call (250 bytes per `get`, with the descent and the scan inside `search` both inlined that
// way, and `get` about half as slow again in a coarse measurement). So nothing on a hot path here
// is a function with one caller:
//
// - each descent is a loop written out in the function that needs it, rather than a call to a
//   function in `Node` that nothing else would call;
// - what they do call is either used from several places (`Node.search`, the array helpers) or
//   recursive (`Insert.intoNode`, `Delete.fromNode`), neither of which is inlined.

open Node

type t<'k, 'v, 'id> = {
  root: option<Node.t<'k, 'v>>,
  compare: ('k, 'k) => int,
  // The most keys a leaf, or children an internal node, may hold.
  maxNodeSize: int,
}

/**
The fewest keys or children a node other than the root may hold: half of the maximum, rounded up.
Merging a node one below this with a sibling exactly at it never exceeds the maximum, and
splitting a node one over the maximum leaves both halves at or above it.
*/
let minNodeSize = (maxNodeSize: int): int => Int.shiftRight(maxNodeSize + 1, 1)

/**
Normalizes a requested max node size: below 4 (or omitted) falls back to the default of 32,
above 256 is clamped down to 256. Below 4 leaves no room for the borrow/merge deletion logic to
do its job (a node can't have a meaningful "spare" sibling to borrow from), and above 256 buys
nothing but wasted array copies on every edit.
*/
let clampMaxNodeSize = (maxNodeSize: option<int>): int =>
  switch maxNodeSize {
  | Some(size) if size >= 4 => min(size, 256)
  | _ => 32
  }

// `id`'s type contains the (as yet undetermined) type variables `k`/`id`,
// and extracting the plain comparator function out of it (`unpack`) needs
// them pinned down as genuine, rigid types rather than ordinary inference
// variables -- hence declaring them explicitly with `(type k, type id)`,
// the standard ReScript/OCaml idiom for unpacking a first-class module in
// a still-polymorphic function. `fromArray` below doesn't need this: it
// only ever passes `id` *through* to `make`, never unpacks it itself.
let make = (type k id, ~id: Belt.Id.comparable<k, id>, ~maxNodeSize: option<int>=?): t<
  k,
  'v,
  id,
> => {
  module Cmp = unpack(id)
  {
    root: None,
    compare: Belt.Id.getCmpInternal(Cmp.cmp),
    maxNodeSize: clampMaxNodeSize(maxNodeSize),
  }
}

let maxNodeSize = (tree: t<'k, 'v, 'id>): int => tree.maxNodeSize

let root = (tree: t<'k, 'v, 'id>): option<Node.t<'k, 'v>> => tree.root

// -----------------------------------------------------------------------------
// Lookup
// -----------------------------------------------------------------------------

let get = (tree: t<'k, 'v, 'id>, key: 'k): option<'v> =>
  switch tree.root {
  | None => None
  | Some(root) =>
    let compare = tree.compare
    let node = ref(root)
    while !isLeaf(node.contents) {
      let current = node.contents
      node := childAt(current.links, childIndex(search(current.keys, key, compare)))
    }
    let found = search(node.contents.keys, key, compare)
    found >= 0 ? Some(Array.getUnsafe(node.contents.values, found)) : None
  }

let has = (tree: t<'k, 'v, 'id>, key: 'k): bool =>
  switch tree.root {
  | None => false
  | Some(root) =>
    let compare = tree.compare
    let node = ref(root)
    while !isLeaf(node.contents) {
      let current = node.contents
      node := childAt(current.links, childIndex(search(current.keys, key, compare)))
    }
    search(node.contents.keys, key, compare) >= 0
  }

let size = (tree: t<'k, 'v, 'id>): int =>
  switch tree.root {
  | None => 0
  | Some(root) => Node.size(root)
  }

let isEmpty = (tree: t<'k, 'v, 'id>): bool => tree.root === None

let minKey = (tree: t<'k, 'v, 'id>): option<'k> => tree.root->Option.map(Node.minKey)
let maxKey = (tree: t<'k, 'v, 'id>): option<'k> => tree.root->Option.map(Node.maxKey)

// -----------------------------------------------------------------------------
// Positions
// -----------------------------------------------------------------------------

let getAt = (tree: t<'k, 'v, 'id>, index: int): option<('k, 'v)> =>
  switch tree.root {
  | Some(root) if index >= 0 && index < Node.size(root) =>
    let node = ref(root)
    // The position sought within the subtree at `node`.
    let position = ref(index)
    while !isLeaf(node.contents) {
      let links = node.contents.links
      // Binary search for the first child whose cumulative count is greater than `position`.
      let low = ref(0)
      let high = ref(childCount(links) - 1)
      while low.contents < high.contents {
        let middle = Int.shiftRightUnsigned(low.contents + high.contents, 1)
        if countAt(links, middle) > position.contents {
          high := middle
        } else {
          low := middle + 1
        }
      }
      let child = low.contents
      if child > 0 {
        position := position.contents - countAt(links, child - 1)
      }
      node := childAt(links, child)
    }
    Some((
      Array.getUnsafe(node.contents.keys, position.contents),
      Array.getUnsafe(node.contents.values, position.contents),
    ))
  | _ => None
  }

let indexOf = (tree: t<'k, 'v, 'id>, key: 'k): option<int> =>
  switch tree.root {
  | None => None
  | Some(root) =>
    let compare = tree.compare
    let node = ref(root)
    // The number of entries in the subtrees passed over to the left on the way down.
    let before = ref(0)
    while !isLeaf(node.contents) {
      let current = node.contents
      let links = current.links
      let child = childIndex(search(current.keys, key, compare))
      if child > 0 {
        before := before.contents + countAt(links, child - 1)
      }
      node := childAt(links, child)
    }
    let found = search(node.contents.keys, key, compare)
    found >= 0 ? Some(before.contents + found) : None
  }

// -----------------------------------------------------------------------------
// Edits (these all return a new tree, never touching the one given)
// -----------------------------------------------------------------------------

let set = (tree: t<'k, 'v, 'id>, key: 'k, value: 'v): t<'k, 'v, 'id> =>
  switch tree.root {
  | None => {root: Some(leaf([key], [value])), compare: tree.compare, maxNodeSize: tree.maxNodeSize}
  | Some(root) =>
    let state: Insert.state<'k, 'v> = {grew: false, splitKey: key, splitRight: None}
    let newNode = Insert.intoNode(root, key, value, tree.compare, tree.maxNodeSize, state)
    if newNode === root {
      tree
    } else {
      let newRoot = switch state.splitRight {
      | None => newNode
      | Some(right) =>
        // The root split: the tree grows a level.
        let leftSize = Node.size(newNode)
        internal(
          [state.splitKey],
          [Child(newNode), Count(leftSize), Child(right), Count(leftSize + Node.size(right))],
        )
      }
      {root: Some(newRoot), compare: tree.compare, maxNodeSize: tree.maxNodeSize}
    }
  }

let remove = (tree: t<'k, 'v, 'id>, key: 'k): t<'k, 'v, 'id> =>
  switch tree.root {
  | None => tree
  | Some(root) =>
    let newNode = Delete.fromNode(root, key, tree.compare, minNodeSize(tree.maxNodeSize))
    if newNode === root {
      tree
    } else {
      let newRoot = if isLeaf(newNode) {
        // A root may be any size but empty.
        Array.length(newNode.keys) == 0 ? None : Some(newNode)
      } else if childCount(newNode.links) == 1 {
        // A merge left the root with a single child, which can be the root itself.
        Some(childAt(newNode.links, 0))
      } else {
        Some(newNode)
      }
      {root: newRoot, compare: tree.compare, maxNodeSize: tree.maxNodeSize}
    }
  }

/** Whether `entries` is in strictly ascending key order (so also free of duplicate keys). */
let isStrictlyAscending = (entries: array<('k, 'v)>, ~compare: ('k, 'k) => int): bool => {
  let ascending = ref(true)
  let index = ref(1)
  while ascending.contents && index.contents < Array.length(entries) {
    let (previousKey, _) = Array.getUnsafe(entries, index.contents - 1)
    let (key, _) = Array.getUnsafe(entries, index.contents)
    ascending := compare(previousKey, key) < 0
    index := index.contents + 1
  }
  ascending.contents
}

let fromArray = (
  ~id: Belt.Id.comparable<'k, 'id>,
  ~maxNodeSize: option<int>=?,
  entries: array<('k, 'v)>,
): t<'k, 'v, 'id> => {
  let empty = make(~id, ~maxNodeSize?)
  if isStrictlyAscending(entries, ~compare=empty.compare) {
    {...empty, root: fromSorted(entries, ~maxNodeSize=empty.maxNodeSize)}
  } else {
    Array.reduce(entries, empty, (tree, (key, value)) => set(tree, key, value))
  }
}

// -----------------------------------------------------------------------------
// Traversal
// -----------------------------------------------------------------------------

let forEach = (tree: t<'k, 'v, 'id>, callback: ('k, 'v) => unit): unit =>
  switch tree.root {
  | None => ()
  | Some(root) => Node.forEach(root, callback)
  }

let reduce = (tree: t<'k, 'v, 'id>, initial: 'acc, callback: ('acc, 'k, 'v) => 'acc): 'acc =>
  switch tree.root {
  | None => initial
  | Some(root) => Node.reduce(root, initial, callback)
  }

let toArray = (tree: t<'k, 'v, 'id>): array<('k, 'v)> => {
  let result = []
  switch tree.root {
  | None => ()
  | Some(root) => pushEntries(root, result)
  }
  result
}

let keysArray = (tree: t<'k, 'v, 'id>): array<'k> => {
  let result = []
  switch tree.root {
  | None => ()
  | Some(root) => pushKeys(root, result)
  }
  result
}

let valuesArray = (tree: t<'k, 'v, 'id>): array<'v> => {
  let result = []
  switch tree.root {
  | None => ()
  | Some(root) => pushValues(root, result)
  }
  result
}

// -----------------------------------------------------------------------------
// Diffing and diagnostics
// -----------------------------------------------------------------------------

// See `Diff` for how this stays cheap when `left` and `right` share structure.
let diff = (
  left: t<'k, 'v, 'id>,
  right: t<'k, 'v, 'id>,
  ~valueEqual: ('v, 'v) => bool=(a, b) => a === b,
  ~onlyLeft: ('k, 'v) => unit=(_, _) => (),
  ~onlyRight: ('k, 'v) => unit=(_, _) => (),
  ~different: ('k, 'v, 'v) => unit=(_, _, _) => (),
): unit =>
  Diff.run(
    left.root,
    right.root,
    ~compare=left.compare,
    ~valueEqual,
    ~onlyLeft,
    ~onlyRight,
    ~different,
  )->ignore

let sharedSubtreeCount = (left: t<'k, 'v, 'id>, right: t<'k, 'v, 'id>): int =>
  Diff.run(
    left.root,
    right.root,
    ~compare=left.compare,
    ~valueEqual=(_, _) => true,
    ~onlyLeft=(_, _) => (),
    ~onlyRight=(_, _) => (),
    ~different=(_, _, _) => (),
  )

let checkInvariants = (tree: t<'k, 'v, 'id>): unit =>
  switch tree.root {
  | None => ()
  | Some(root) =>
    check(
      root,
      ~compare=tree.compare,
      ~minSize=minNodeSize(tree.maxNodeSize),
      ~maxSize=tree.maxNodeSize,
      ~isRoot=true,
      ~lower=None,
      ~upper=None,
    )->ignore
  }
