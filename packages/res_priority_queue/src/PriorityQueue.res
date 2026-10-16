// See `PriorityQueue.resi` for what this module does and why it
// exists; this file holds the leftist-heap implementation notes.
//
// A leftist heap is a binary tree where every node's priority is at least that
// of its children (so the highest-priority value -- the minimum by `cmp` -- is
// always at the root), and each node tracks its "rank": the length of its
// *right spine* (the path following only right children down to a leaf; an
// absent child has rank `0`). The leftist property is that every node's left
// child has rank >= its right child's -- which is what keeps the right spine
// short (`O(log n)`) and makes `mergeNodes` the one operation everything else is
// built from, itself only `O(log n)`: it walks down the (short) right spines of
// both heaps, merging them like two sorted lists, then swaps children as needed
// on the way back up to restore the leftist property. `enqueue`/`dequeue` are
// then just "merge a singleton in" / "merge the root's two children together."

type rec node<'a> = {
  value: 'a,
  rank: int,
  left: option<node<'a>>,
  right: option<node<'a>>,
}

type t<'a, 'id> = {
  cmp: ('a, 'a) => int,
  root: option<node<'a>>,
  size: int,
}

let rankOf = (node: option<node<'a>>): int =>
  switch node {
  | None => 0
  | Some(node) => node.rank
  }

let rec mergeNodes = (cmp: ('a, 'a) => int, a: option<node<'a>>, b: option<node<'a>>): option<
  node<'a>,
> =>
  switch (a, b) {
  | (None, b) => b
  | (a, None) => a
  | (Some(nodeA), Some(nodeB)) =>
    let (smaller, larger) = if cmp(nodeA.value, nodeB.value) <= 0 {
      (nodeA, nodeB)
    } else {
      (nodeB, nodeA)
    }
    let mergedRight = mergeNodes(cmp, smaller.right, Some(larger))
    let leftRank = rankOf(smaller.left)
    let rightRank = rankOf(mergedRight)

    // Keep the leftist property: the left child's rank must be >= the
    // right's, swapping them if the merge just made the right side longer.
    if leftRank >= rightRank {
      Some({value: smaller.value, rank: rightRank + 1, left: smaller.left, right: mergedRight})
    } else {
      Some({value: smaller.value, rank: leftRank + 1, left: mergedRight, right: smaller.left})
    }
  }

let make = (type a id, ~id: Belt.Id.comparable<a, id>): t<a, id> => {
  module Cmp = unpack(id)
  {cmp: Belt.Id.getCmpInternal(Cmp.cmp), root: None, size: 0}
}

// Folds `enqueue`'s merge over `items` -- `O(n log n)`, not the `O(n)` a
// pairwise-merge construction could achieve. Kept simple deliberately: this
// package's `MutablePriorityQueue.fromArray` already covers the case where
// construction speed actually matters (its `buildHeap` really is `O(n)`), and
// reaching for the same trick here would mean building a queue-of-singletons
// merge loop, which doesn't pull its weight for a structure whose whole point is
// being simple to read.
let fromArray = (type a id, items: array<a>, ~id: Belt.Id.comparable<a, id>): t<a, id> =>
  Array.reduce(items, make(~id), (queue, value) => {
    cmp: queue.cmp,
    root: mergeNodes(queue.cmp, Some({value, rank: 1, left: None, right: None}), queue.root),
    size: queue.size + 1,
  })

let enqueue = (t: t<'a, 'id>, value: 'a): t<'a, 'id> => {
  cmp: t.cmp,
  root: mergeNodes(t.cmp, Some({value, rank: 1, left: None, right: None}), t.root),
  size: t.size + 1,
}

let peek = (t: t<'a, 'id>): option<'a> =>
  switch t.root {
  | None => None
  | Some(node) => Some(node.value)
  }

let peekExn = (t: t<'a, 'id>): 'a =>
  switch peek(t) {
  | Some(value) => value
  | None => ResCommon.Debug.fail(~message=() => "PriorityQueue.peekExn: queue is empty")
  }

// A tupled result (rather than two separate functions, `peek`/`withoutMin`)
// since the two are almost always wanted together, and computing them together
// means `dequeue` only ever merges the root's children once.
let dequeue = (t: t<'a, 'id>): option<('a, t<'a, 'id>)> =>
  switch t.root {
  | None => None
  | Some(node) =>
    Some((
      node.value,
      {cmp: t.cmp, root: mergeNodes(t.cmp, node.left, node.right), size: t.size - 1},
    ))
  }

let dequeueExn = (t: t<'a, 'id>): ('a, t<'a, 'id>) =>
  switch dequeue(t) {
  | Some(result) => result
  | None => ResCommon.Debug.fail(~message=() => "PriorityQueue.dequeueExn: queue is empty")
  }

let isEmpty = (t: t<'a, 'id>): bool => t.root->Option.isNone
let size = (t: t<'a, 'id>): int => t.size

// Repeatedly dequeues into a plain array. Since `t` is persistent this doesn't
// consume it -- each `dequeue` just yields the next, smaller queue.
let toArray = (t: t<'a, 'id>): array<'a> => {
  let result = []
  let current = ref(t)
  let keepGoing = ref(true)
  while keepGoing.contents {
    switch dequeue(current.contents) {
    | None => keepGoing := false
    | Some((value, rest)) =>
      Array.push(result, value)
      current := rest
    }
  }
  result
}
