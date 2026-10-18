open Vitest

let id = TestSupport.intId

describe("PriorityQueue: construction", () => {
  test("make is empty", t => {
    let q = PriorityQueue.make(~id)
    t->expect(PriorityQueue.isEmpty(q))->Expect.toBeTruthy
    t->expect(PriorityQueue.size(q))->Expect.toBe(0)
    t->expect(PriorityQueue.peek(q))->Expect.toBeNone
    t->expect(PriorityQueue.dequeue(q))->Expect.toBeNone
  })

  test("fromArray preserves size/contents in ascending order", t => {
    let q = PriorityQueue.fromArray([5, 3, 8, 1, 9, 2], ~id)
    t->expect(PriorityQueue.size(q))->Expect.toBe(6)
    t->expect(PriorityQueue.toArray(q))->Expect.toEqual([1, 2, 3, 5, 8, 9])
  })

  test("fromArray with an empty array is an empty queue", t => {
    let q = PriorityQueue.fromArray([], ~id)
    t->expect(PriorityQueue.isEmpty(q))->Expect.toBeTruthy
  })

  test("fromArray does not mutate the array it was given", t => {
    let source = [5, 3, 8]
    let _ = PriorityQueue.fromArray(source, ~id)
    t->expect(source)->Expect.toEqual([5, 3, 8])
  })
})

describe("PriorityQueue: enqueue/dequeue order", () => {
  test("drains in ascending order for the default int comparator", t => {
    let q =
      [5, 3, 8, 1, 9, 2, 7]->Array.reduce(
        PriorityQueue.make(~id),
        (q, v) => PriorityQueue.enqueue(q, v),
      )
    t->expect(PriorityQueue.toArray(q))->Expect.toEqual([1, 2, 3, 5, 7, 8, 9])
  })

  test("a single element enqueues and dequeues correctly", t => {
    let q = PriorityQueue.enqueue(PriorityQueue.make(~id), 42)
    t->expect(PriorityQueue.peek(q))->Expect.toEqual(Some(42))
    let (value, rest) = PriorityQueue.dequeueExn(q)
    t->expect(value)->Expect.toBe(42)
    t->expect(PriorityQueue.isEmpty(rest))->Expect.toBeTruthy
  })

  test("equal-priority elements are all eventually dequeued", t => {
    let q = [3, 3, 3]->Array.reduce(PriorityQueue.make(~id), (q, v) => PriorityQueue.enqueue(q, v))
    t->expect(PriorityQueue.size(q))->Expect.toBe(3)
    t->expect(PriorityQueue.toArray(q))->Expect.toEqual([3, 3, 3])
  })

  test("peek and dequeue never mutate -- the original queue is unaffected", t => {
    let original = PriorityQueue.fromArray([5, 3, 8], ~id)
    let _ = PriorityQueue.peek(original)
    let (_, _rest) = PriorityQueue.dequeueExn(original)
    t->expect(PriorityQueue.size(original))->Expect.toBe(3)
    t->expect(PriorityQueue.toArray(original))->Expect.toEqual([3, 5, 8])
  })

  test("a snapshot taken before further enqueues/dequeues stays frozen", t => {
    let snapshot = PriorityQueue.fromArray([5, 3, 8], ~id)
    let _laterQueue = snapshot->PriorityQueue.enqueue(1)->PriorityQueue.dequeueExn->Pair.second
    t->expect(PriorityQueue.toArray(snapshot))->Expect.toEqual([3, 5, 8])
  })

  test("dequeue/peek/peekExn/dequeueExn on an empty queue", t => {
    let q = PriorityQueue.make(~id)
    t->expect(PriorityQueue.dequeue(q))->Expect.toBeNone
    t->expect(PriorityQueue.peek(q))->Expect.toBeNone
    t->expect(() => PriorityQueue.dequeueExn(q))->Expect.toThrow
    t->expect(() => PriorityQueue.peekExn(q))->Expect.toThrow
  })

  test("a custom (max-heap) comparator reverses the order", t => {
    module MaxCmp = Belt.Id.MakeComparable({
      type t = int
      let cmp = (a: int, b: int) => b - a
    })
    let maxId: Belt.Id.comparable<int, MaxCmp.identity> = module(MaxCmp)
    let q = PriorityQueue.fromArray([5, 3, 8, 1, 9], ~id=maxId)
    t->expect(PriorityQueue.toArray(q))->Expect.toEqual([9, 8, 5, 3, 1])
  })
})

describe("PriorityQueue: oracle stress test against a sorted mutable array", () => {
  test("interleaved enqueue/dequeue matches always-dequeue-the-minimum semantics", t => {
    let random = TestSupport.Random.make(31415.0)
    let queue = ref(PriorityQueue.make(~id))
    let oracle = []

    for _ in 1 to 1000 {
      if Array.length(oracle) > 0 && TestSupport.Random.nextInt(random, 3) == 0 {
        Belt.SortArray.stableSortInPlaceBy(oracle, (a, b) => a - b)
        let expectedMin = Array.getUnsafe(oracle, 0)
        let _ = Array.shift(oracle)
        let (value, rest) = PriorityQueue.dequeueExn(queue.contents)
        t->expect(value)->Expect.toBe(expectedMin)
        queue := rest
      } else {
        let value = TestSupport.Random.nextInt(random, 1000)
        queue := PriorityQueue.enqueue(queue.contents, value)
        Array.push(oracle, value)
      }
      t->expect(PriorityQueue.size(queue.contents))->Expect.toBe(Array.length(oracle))
    }

    Belt.SortArray.stableSortInPlaceBy(oracle, (a, b) => a - b)
    t->expect(PriorityQueue.toArray(queue.contents))->Expect.toEqual(oracle)
  })
})
