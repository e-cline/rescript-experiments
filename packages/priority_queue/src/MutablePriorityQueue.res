// See `MutablePriorityQueue.resi` for what this does and how priority is
// expressed.
//
// Both `siftUp`/`siftDown` use the "hole percolation" optimization: the moving
// element is only written into the backing array once, at
// its final resting index, rather than swapped at every level.

type t<'a, 'id> = {
  cmp: ('a, 'a) => int,
  mutable heap: array<'a>,
}

let getParentIndex = (index: int): int => (index - 1) / 2
let getLeftChildIndex = (index: int): int => 2 * index + 1

let siftUp = (t: t<'a, 'id>): unit => {
  let currentIndex = ref(Array.length(t.heap) - 1)
  let value = Array.getUnsafe(t.heap, currentIndex.contents)
  let keepGoing = ref(true)
  while keepGoing.contents && currentIndex.contents > 0 {
    let parentIndex = getParentIndex(currentIndex.contents)
    let parent = Array.getUnsafe(t.heap, parentIndex)
    if t.cmp(value, parent) >= 0 {
      keepGoing := false
    } else {
      Belt.Array.setUnsafe(t.heap, currentIndex.contents, parent)
      currentIndex := parentIndex
    }
  }
  Belt.Array.setUnsafe(t.heap, currentIndex.contents, value)
}

let siftDown = (t: t<'a, 'id>, startIndex: int): unit => {
  let currentIndex = ref(startIndex)
  let heapSize = Array.length(t.heap)
  let value = Array.getUnsafe(t.heap, currentIndex.contents)
  let keepGoing = ref(true)
  while keepGoing.contents {
    let leftChildIndex = getLeftChildIndex(currentIndex.contents)
    if leftChildIndex >= heapSize {
      keepGoing := false
    } else {
      let rightChildIndex = leftChildIndex + 1
      let priorityChildIndex = ref(leftChildIndex)
      let priorityChild = ref(Array.getUnsafe(t.heap, leftChildIndex))
      if rightChildIndex < heapSize {
        let rightChild = Array.getUnsafe(t.heap, rightChildIndex)
        if t.cmp(rightChild, priorityChild.contents) < 0 {
          priorityChildIndex := rightChildIndex
          priorityChild := rightChild
        }
      }
      if t.cmp(value, priorityChild.contents) <= 0 {
        keepGoing := false
      } else {
        Belt.Array.setUnsafe(t.heap, currentIndex.contents, priorityChild.contents)
        currentIndex := priorityChildIndex.contents
      }
    }
  }
  Belt.Array.setUnsafe(t.heap, currentIndex.contents, value)
}

let buildHeap = (t: t<'a, 'id>): unit => {
  let firstNonLeafIndex = Array.length(t.heap) / 2 - 1
  for i in firstNonLeafIndex downto 0 {
    siftDown(t, i)
  }
}

let make = (type a id, ~id: Belt.Id.comparable<a, id>): t<a, id> => {
  module Cmp = unpack(id)
  {cmp: Belt.Id.getCmpInternal(Cmp.cmp), heap: []}
}

let fromArray = (type a id, items: array<a>, ~id: Belt.Id.comparable<a, id>): t<a, id> => {
  let t = make(~id)
  t.heap = Belt.Array.copy(items)
  if Array.length(t.heap) > 0 {
    buildHeap(t)
  }
  t
}

let enqueue = (t: t<'a, 'id>, value: 'a): unit => {
  Array.push(t.heap, value)
  siftUp(t)
}

let dequeue = (t: t<'a, 'id>): option<'a> =>
  switch Array.length(t.heap) {
  | 0 => None
  | 1 => Array.pop(t.heap)
  | _ => {
      let top = Array.getUnsafe(t.heap, 0)
      let last = Array.pop(t.heap)->Belt.Option.getUnsafe
      Belt.Array.setUnsafe(t.heap, 0, last)
      siftDown(t, 0)
      Some(top)
    }
  }

let dequeueExn = (t: t<'a, 'id>): 'a =>
  switch dequeue(t) {
  | Some(value) => value
  | None => Common.Debug.fail(~message=() => "MutablePriorityQueue.dequeueExn: queue is empty")
  }

let peek = (t: t<'a, 'id>): option<'a> => t.heap[0]

let peekExn = (t: t<'a, 'id>): 'a =>
  switch peek(t) {
  | Some(value) => value
  | None => Common.Debug.fail(~message=() => "MutablePriorityQueue.peekExn: queue is empty")
  }

let isEmpty = (t: t<'a, 'id>): bool => Array.length(t.heap) == 0
let size = (t: t<'a, 'id>): int => Array.length(t.heap)
let clear = (t: t<'a, 'id>): unit => t.heap = []
let toArray = (t: t<'a, 'id>): array<'a> => Belt.Array.copy(t.heap)
