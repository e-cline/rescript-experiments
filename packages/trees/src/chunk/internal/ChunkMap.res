/***
`ChunkTree`'s operations at any leaf size: functions of a root and a comparator, with the leaf
size passed to the few that need it (`set`, `remove`, `fromArray`, `checkInvariants`).
`ChunkTree.Make` fixes the size and gives them `AvlTree`'s interface. The node is in `ChunkNode`
and the diff in `ChunkDiff`.
*/

/**
A tree is its root paired with its comparator, as in `AvlTree`. An empty tree has no root.
*/
type tree<'k, 'v, 'id> = {
  root: ChunkNode.tree<'k, 'v>,
  compare: ('k, 'k) => int,
}

// See `BTree.make` for why `k`/`id` are declared as locally abstract types.
let make = (type k id, ~id: Belt.Id.comparable<k, id>): tree<k, 'v, id> => {
  module Cmp = unpack(id)
  {root: None, compare: Belt.Id.getCmpInternal(Cmp.cmp)}
}

// -----------------------------------------------------------------------------
// Lookup
// -----------------------------------------------------------------------------

let get = (root: ChunkNode.tree<'k, 'v>, key: 'k, ~compare: ('k, 'k) => int): option<'v> =>
  switch root {
  | None => None
  | Some(node) =>
    let leaf = ChunkNode.findLeaf(node, key, ~compare)
    let index = ChunkNode.search(leaf.keys, key, ~compare)
    index >= 0 ? Some(Array.getUnsafe(leaf.values, index)) : None
  }

let has = (root: ChunkNode.tree<'k, 'v>, key: 'k, ~compare: ('k, 'k) => int): bool =>
  switch root {
  | None => false
  | Some(node) => ChunkNode.search(ChunkNode.findLeaf(node, key, ~compare).keys, key, ~compare) >= 0
  }

let size = (root: ChunkNode.tree<'k, 'v>): int =>
  switch root {
  | None => 0
  | Some(node) => node.size
  }

let minKey = (root: ChunkNode.tree<'k, 'v>): option<'k> =>
  switch root {
  | None => None
  | Some(node) => Some(ChunkNode.minLeaf(node).key)
  }

let maxKey = (root: ChunkNode.tree<'k, 'v>): option<'k> =>
  switch root {
  | None => None
  | Some(node) =>
    let keys = ChunkNode.maxLeaf(node).keys
    Some(Array.getUnsafe(keys, Array.length(keys) - 1))
  }

// -----------------------------------------------------------------------------
// Order statistics
// -----------------------------------------------------------------------------

let getAt = (root: ChunkNode.tree<'k, 'v>, index: int): option<('k, 'v)> =>
  switch root {
  | Some(root) if index >= 0 && index < root.size =>
    // Descending, the size of a node's left subtree says how many entries sort before its right.
    let node = ref(root)
    let position = ref(index)
    while node.contents.height > 1 {
      let left = node.contents.left
      if position.contents < left.size {
        node := left
      } else {
        position := position.contents - left.size
        node := node.contents.right
      }
    }
    Some((
      Array.getUnsafe(node.contents.keys, position.contents),
      Array.getUnsafe(node.contents.values, position.contents),
    ))
  | _ => None
  }

let indexOf = (root: ChunkNode.tree<'k, 'v>, key: 'k, ~compare: ('k, 'k) => int): option<int> =>
  switch root {
  | None => None
  | Some(root) =>
    let node = ref(root)
    // The number of entries known to sort before everything under `node`.
    let skipped = ref(0)
    while node.contents.height > 1 {
      let current = node.contents
      if compare(key, current.key) < 0 {
        node := current.left
      } else {
        skipped := skipped.contents + current.left.size
        node := current.right
      }
    }
    let index = ChunkNode.search(node.contents.keys, key, ~compare)
    index >= 0 ? Some(skipped.contents + index) : None
  }

// -----------------------------------------------------------------------------
// Mutation (persistent -- these all return a new tree, never touching `tree`)
// -----------------------------------------------------------------------------

let set = (tree: tree<'k, 'v, 'id>, key: 'k, value: 'v, ~maxLeafSize: int): tree<'k, 'v, 'id> =>
  switch tree.root {
  | None => {root: Some(ChunkNode.makeLeaf([key], [value])), compare: tree.compare}
  | Some(node) =>
    let newNode = ChunkNode.set(node, key, value, ~compare=tree.compare, ~max=maxLeafSize)
    newNode === node ? tree : {root: Some(newNode), compare: tree.compare}
  }

let remove = (tree: tree<'k, 'v, 'id>, key: 'k, ~maxLeafSize: int): tree<'k, 'v, 'id> =>
  switch tree.root {
  | None => tree
  | Some(node) =>
    let newNode = ChunkNode.removeFrom(node, key, ~compare=tree.compare, ~max=maxLeafSize)
    if newNode === node {
      tree
    } else {
      // Only a root that is a leaf can come back empty.
      {root: newNode.size == 0 ? None : Some(newNode), compare: tree.compare}
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
  entries: array<('k, 'v)>,
  ~maxLeafSize: int,
): tree<'k, 'v, 'id> => {
  let empty = make(~id)
  if isStrictlyAscending(entries, ~compare=empty.compare) {
    // `map` gives packed arrays of the narrowest kind the keys and values allow, the same kind
    // a tree grown by `set` has; the leaves are slices of them.
    let keys = entries->Array.map(((key, _)) => key)
    let values = entries->Array.map(((_, value)) => value)
    {root: ChunkNode.fromSortedArrays(keys, values, ~max=maxLeafSize), compare: empty.compare}
  } else {
    Array.reduce(entries, empty, (tree, (key, value)) => set(tree, key, value, ~maxLeafSize))
  }
}

// -----------------------------------------------------------------------------
// Traversal / conversion
// -----------------------------------------------------------------------------

let forEach = (root: ChunkNode.tree<'k, 'v>, callback: ('k, 'v) => unit): unit =>
  switch root {
  | None => ()
  | Some(node) => ChunkNode.forEach(node, callback)
  }

let reduce = (
  root: ChunkNode.tree<'k, 'v>,
  initial: 'acc,
  callback: ('acc, 'k, 'v) => 'acc,
): 'acc =>
  switch root {
  | None => initial
  | Some(node) => ChunkNode.reduce(node, initial, callback)
  }

// The three array builders allocate the result at its final length and have each leaf write its
// entries into place.

let toArray = (root: ChunkNode.tree<'k, 'v>): array<('k, 'v)> =>
  switch root {
  | None => []
  | Some(node) =>
    let result = Belt.Array.makeUninitializedUnsafe(node.size)
    ChunkNode.fillEntries(node, result, 0)
    result
  }

let keysArray = (root: ChunkNode.tree<'k, 'v>): array<'k> =>
  switch root {
  | None => []
  | Some(node) =>
    let result = Belt.Array.makeUninitializedUnsafe(node.size)
    ChunkNode.fillKeys(node, result, 0)
    result
  }

let valuesArray = (root: ChunkNode.tree<'k, 'v>): array<'v> =>
  switch root {
  | None => []
  | Some(node) =>
    let result = Belt.Array.makeUninitializedUnsafe(node.size)
    ChunkNode.fillValues(node, result, 0)
    result
  }

// -----------------------------------------------------------------------------
// Diffing and diagnostics
// -----------------------------------------------------------------------------

// See `ChunkDiff.res` for how this stays cheap when `left` and `right` share structure.
let diff = (
  left: ChunkNode.tree<'k, 'v>,
  right: ChunkNode.tree<'k, 'v>,
  ~compare: ('k, 'k) => int,
  ~valueEqual: ('v, 'v) => bool=(a, b) => a === b,
  ~onlyLeft: ('k, 'v) => unit=(_, _) => (),
  ~onlyRight: ('k, 'v) => unit=(_, _) => (),
  ~different: ('k, 'v, 'v) => unit=(_, _, _) => (),
): unit =>
  ChunkDiff.run(
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
  left: ChunkNode.tree<'k, 'v>,
  right: ChunkNode.tree<'k, 'v>,
  ~compare: ('k, 'k) => int,
): int => {
  let count = ref(0)
  ChunkDiff.run(
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

let checkInvariants = (tree: tree<'k, 'v, 'id>, ~maxLeafSize: int): unit =>
  ChunkNode.checkInvariants(tree.root, ~compare=tree.compare, ~max=maxLeafSize)
