open Vitest

let id = TestSupport.intId

describe("MutablePriorityQueue: construction", () => {
  test("make is empty", t => {
    let q = MutablePriorityQueue.make(~id)
    t->expect(MutablePriorityQueue.isEmpty(q))->Expect.toBeTruthy
    t->expect(MutablePriorityQueue.size(q))->Expect.toBe(0)
    t->expect(MutablePriorityQueue.peek(q))->Expect.toBeNone
    t->expect(MutablePriorityQueue.dequeue(q))->Expect.toBeNone
  })

  test("fromArray heapifies in one shot and preserves size/contents", t => {
    let q = MutablePriorityQueue.fromArray([5, 3, 8, 1, 9, 2], ~id)
    t->expect(MutablePriorityQueue.size(q))->Expect.toBe(6)
    let drained = []
    while !MutablePriorityQueue.isEmpty(q) {
      Array.push(drained, MutablePriorityQueue.dequeueExn(q))
    }
    t->expect(drained)->Expect.toEqual([1, 2, 3, 5, 8, 9])
  })

  test("fromArray with an empty array is an empty queue", t => {
    let q = MutablePriorityQueue.fromArray([], ~id)
    t->expect(MutablePriorityQueue.isEmpty(q))->Expect.toBeTruthy
  })

  test("fromArray does not mutate the array it was given", t => {
    let source = [5, 3, 8]
    let _ = MutablePriorityQueue.fromArray(source, ~id)
    t->expect(source)->Expect.toEqual([5, 3, 8])
  })
})

describe("MutablePriorityQueue: enqueue/dequeue order", () => {
  test("dequeues in ascending order for the default int comparator", t => {
    let q = MutablePriorityQueue.make(~id)
    [5, 3, 8, 1, 9, 2, 7]->Array.forEach(v => MutablePriorityQueue.enqueue(q, v))
    let drained = []
    while !MutablePriorityQueue.isEmpty(q) {
      Array.push(drained, MutablePriorityQueue.dequeueExn(q))
    }
    t->expect(drained)->Expect.toEqual([1, 2, 3, 5, 7, 8, 9])
  })

  test("a single element enqueues and dequeues correctly", t => {
    let q = MutablePriorityQueue.make(~id)
    MutablePriorityQueue.enqueue(q, 42)
    t->expect(MutablePriorityQueue.peek(q))->Expect.toEqual(Some(42))
    t->expect(MutablePriorityQueue.dequeue(q))->Expect.toEqual(Some(42))
    t->expect(MutablePriorityQueue.isEmpty(q))->Expect.toBeTruthy
  })

  test("equal-priority elements are all eventually dequeued", t => {
    let q = MutablePriorityQueue.make(~id)
    [3, 3, 3]->Array.forEach(v => MutablePriorityQueue.enqueue(q, v))
    t->expect(MutablePriorityQueue.size(q))->Expect.toBe(3)
    let drained = []
    while !MutablePriorityQueue.isEmpty(q) {
      Array.push(drained, MutablePriorityQueue.dequeueExn(q))
    }
    t->expect(drained)->Expect.toEqual([3, 3, 3])
  })

  test("peek never removes the element", t => {
    let q = MutablePriorityQueue.make(~id)
    MutablePriorityQueue.enqueue(q, 1)
    let _ = MutablePriorityQueue.peek(q)
    let _ = MutablePriorityQueue.peek(q)
    t->expect(MutablePriorityQueue.size(q))->Expect.toBe(1)
  })

  test("dequeue/peek/peekExn/dequeueExn on an empty queue", t => {
    let q = MutablePriorityQueue.make(~id)
    t->expect(MutablePriorityQueue.dequeue(q))->Expect.toBeNone
    t->expect(MutablePriorityQueue.peek(q))->Expect.toBeNone
    t->expect(() => MutablePriorityQueue.dequeueExn(q))->Expect.toThrow
    t->expect(() => MutablePriorityQueue.peekExn(q))->Expect.toThrow
  })

  test("clear empties the queue", t => {
    let q = MutablePriorityQueue.fromArray([1, 2, 3], ~id)
    MutablePriorityQueue.clear(q)
    t->expect(MutablePriorityQueue.isEmpty(q))->Expect.toBeTruthy
    t->expect(MutablePriorityQueue.size(q))->Expect.toBe(0)
  })

  test("a custom (max-heap) comparator reverses the order", t => {
    module MaxCmp = Belt.Id.MakeComparable({
      type t = int
      let cmp = (a: int, b: int) => b - a
    })
    let maxId: Belt.Id.comparable<int, MaxCmp.identity> = module(MaxCmp)
    let q = MutablePriorityQueue.fromArray([5, 3, 8, 1, 9], ~id=maxId)
    let drained = []
    while !MutablePriorityQueue.isEmpty(q) {
      Array.push(drained, MutablePriorityQueue.dequeueExn(q))
    }
    t->expect(drained)->Expect.toEqual([9, 8, 5, 3, 1])
  })
})

describe("MutablePriorityQueue: oracle stress test against a sorted mutable array", () => {
  test("interleaved enqueue/dequeue matches always-dequeue-the-minimum semantics", t => {
    let random = TestSupport.Random.make(9001.0)
    let q = MutablePriorityQueue.make(~id)
    let oracle = []

    for _ in 1 to 1000 {
      if Array.length(oracle) > 0 && TestSupport.Random.nextInt(random, 3) == 0 {
        // Dequeue: the oracle's minimum must match the queue's.
        Belt.SortArray.stableSortInPlaceBy(oracle, (a, b) => a - b)
        let expectedMin = Array.getUnsafe(oracle, 0)
        let _ = Array.shift(oracle)
        t->expect(MutablePriorityQueue.dequeueExn(q))->Expect.toBe(expectedMin)
      } else {
        let value = TestSupport.Random.nextInt(random, 1000)
        MutablePriorityQueue.enqueue(q, value)
        Array.push(oracle, value)
      }
      t->expect(MutablePriorityQueue.size(q))->Expect.toBe(Array.length(oracle))
    }

    // Drain everything left and confirm it comes out fully sorted.
    Belt.SortArray.stableSortInPlaceBy(oracle, (a, b) => a - b)
    let drained = []
    while !MutablePriorityQueue.isEmpty(q) {
      Array.push(drained, MutablePriorityQueue.dequeueExn(q))
    }
    t->expect(drained)->Expect.toEqual(oracle)
  })
})
