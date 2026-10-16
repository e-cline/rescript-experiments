// A thin facade over `internal/` (`AvlNode`, `AvlDiff`); see `AvlTree.resi` for
// what this module promises. Like `Belt.Map`, a tree is its root paired with the
// comparator it is ordered by. There is no cached size alongside them, as
// `BTree` has: every node carries its own subtree's size, so the root's is the
// tree's.

type t<'k, 'v, 'id> = {
  root: AvlNode.tree<'k, 'v>,
  compare: ('k, 'k) => int,
}

// -----------------------------------------------------------------------------
// Construction
// -----------------------------------------------------------------------------

// See `BTree.make` for why `k`/`id` are declared as locally abstract types.
let make = (type k id, ~id: Belt.Id.comparable<k, id>): t<k, 'v, id> => {
  module Cmp = unpack(id)
  {root: None, compare: Belt.Id.getCmpInternal(Cmp.cmp)}
}

// -----------------------------------------------------------------------------
// Lookup
// -----------------------------------------------------------------------------

let get = (tree: t<'k, 'v, 'id>, key: 'k): option<'v> =>
  AvlNode.get(tree.root, key, ~compare=tree.compare)

let has = (tree: t<'k, 'v, 'id>, key: 'k): bool =>
  AvlNode.has(tree.root, key, ~compare=tree.compare)

let size = (tree: t<'k, 'v, 'id>): int => AvlNode.size(tree.root)
let isEmpty = (tree: t<'k, 'v, 'id>): bool => tree.root === None

let minKey = (tree: t<'k, 'v, 'id>): option<'k> => tree.root->Option.map(AvlNode.minKey)
let maxKey = (tree: t<'k, 'v, 'id>): option<'k> => tree.root->Option.map(AvlNode.maxKey)

// -----------------------------------------------------------------------------
// Order statistics
// -----------------------------------------------------------------------------

let getAt = (tree: t<'k, 'v, 'id>, index: int): option<('k, 'v)> =>
  switch tree.root {
  | Some(node) if index >= 0 && index < node.size => Some(AvlNode.getAt(node, index))
  | _ => None
  }

let indexOf = (tree: t<'k, 'v, 'id>, key: 'k): option<int> =>
  AvlNode.indexOf(tree.root, key, ~compare=tree.compare)

// -----------------------------------------------------------------------------
// Mutation (persistent -- these all return a new `t`, never touching `tree`)
// -----------------------------------------------------------------------------

let set = (tree: t<'k, 'v, 'id>, key: 'k, value: 'v): t<'k, 'v, 'id> => {
  let newRoot = Some(AvlNode.set(tree.root, key, value, ~compare=tree.compare))
  newRoot === tree.root ? tree : {root: newRoot, compare: tree.compare}
}

let remove = (tree: t<'k, 'v, 'id>, key: 'k): t<'k, 'v, 'id> => {
  let newRoot = AvlNode.remove(tree.root, key, ~compare=tree.compare)
  newRoot === tree.root ? tree : {root: newRoot, compare: tree.compare}
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

let fromArray = (~id: Belt.Id.comparable<'k, 'id>, entries: array<('k, 'v)>): t<'k, 'v, 'id> => {
  let empty = make(~id)
  if isStrictlyAscending(entries, ~compare=empty.compare) {
    {...empty, root: AvlNode.fromSortedArray(entries)}
  } else {
    Array.reduce(entries, empty, (tree, (key, value)) => set(tree, key, value))
  }
}

// -----------------------------------------------------------------------------
// Traversal / conversion
// -----------------------------------------------------------------------------

let forEach = (tree: t<'k, 'v, 'id>, callback: ('k, 'v) => unit): unit =>
  AvlNode.forEach(tree.root, callback)

let reduce = (tree: t<'k, 'v, 'id>, initial: 'acc, callback: ('acc, 'k, 'v) => 'acc): 'acc =>
  AvlNode.reduce(tree.root, initial, callback)

let toArray = (tree: t<'k, 'v, 'id>): array<('k, 'v)> => AvlNode.toArray(tree.root)
let keysArray = (tree: t<'k, 'v, 'id>): array<'k> => AvlNode.keysArray(tree.root)
let valuesArray = (tree: t<'k, 'v, 'id>): array<'v> => AvlNode.valuesArray(tree.root)

// -----------------------------------------------------------------------------
// Diffing and diagnostics
// -----------------------------------------------------------------------------

// See `internal/AvlDiff.res` for how this stays cheap when `left` and `right`
// share structure.
let diff = (
  left: t<'k, 'v, 'id>,
  right: t<'k, 'v, 'id>,
  ~valueEqual: ('v, 'v) => bool=(a, b) => a === b,
  ~onlyLeft: ('k, 'v) => unit=(_, _) => (),
  ~onlyRight: ('k, 'v) => unit=(_, _) => (),
  ~different: ('k, 'v, 'v) => unit=(_, _, _) => (),
): unit =>
  AvlDiff.diff(
    left.root,
    right.root,
    ~compare=left.compare,
    ~valueEqual,
    ~onlyLeft,
    ~onlyRight,
    ~different,
  )

let sharedSubtreeCount = (left: t<'k, 'v, 'id>, right: t<'k, 'v, 'id>): int =>
  AvlDiff.sharedSubtreeCount(left.root, right.root, ~compare=left.compare)

let checkInvariants = (tree: t<'k, 'v, 'id>): unit =>
  AvlNode.checkInvariants(tree.root, ~compare=tree.compare)
