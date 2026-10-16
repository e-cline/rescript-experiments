open Vitest

describe("ImmutableArray: construction and basic access", () => {
  test("make is empty", t => {
    t->expect(ImmutableArray.length(ImmutableArray.make()))->Expect.toBe(0)
    t->expect(ImmutableArray.isEmpty(ImmutableArray.make()))->Expect.toBeTruthy
  })

  test("fromArray/toArray round-trips", t => {
    let t_ = ImmutableArray.fromArray([1, 2, 3])
    t->expect(ImmutableArray.toArray(t_))->Expect.toEqual([1, 2, 3])
    t->expect(ImmutableArray.length(t_))->Expect.toBe(3)
  })

  test("fromArray copies, so mutating the source afterward has no effect", t => {
    let source = [1, 2, 3]
    let t_ = ImmutableArray.fromArray(source)
    source[0] = 999
    t->expect(ImmutableArray.toArray(t_))->Expect.toEqual([1, 2, 3])
  })

  test("toArray copies, so mutating the result has no effect on the original", t => {
    let t_ = ImmutableArray.fromArray([1, 2, 3])
    let out = ImmutableArray.toArray(t_)
    out[0] = 999
    t->expect(ImmutableArray.toArray(t_))->Expect.toEqual([1, 2, 3])
  })

  test("get returns None out of bounds, Some in bounds", t => {
    let t_ = ImmutableArray.fromArray([10, 20, 30])
    t->expect(ImmutableArray.get(t_, 1))->Expect.toEqual(Some(20))
    t->expect(ImmutableArray.get(t_, 3))->Expect.toBeNone
    t->expect(ImmutableArray.get(t_, -1))->Expect.toBeNone
  })

  test("getExn returns the value in bounds, throws out of bounds", t => {
    let t_ = ImmutableArray.fromArray([10, 20, 30])
    t->expect(ImmutableArray.getExn(t_, 1))->Expect.toBe(20)
    t->expect(() => ImmutableArray.getExn(t_, 3))->Expect.toThrow
  })

  test("first/last on an empty array are None", t => {
    let t_ = ImmutableArray.make()
    t->expect(ImmutableArray.first(t_))->Expect.toBeNone
    t->expect(ImmutableArray.last(t_))->Expect.toBeNone
  })

  test("first/last on a non-empty array", t => {
    let t_ = ImmutableArray.fromArray([1, 2, 3])
    t->expect(ImmutableArray.first(t_))->Expect.toEqual(Some(1))
    t->expect(ImmutableArray.last(t_))->Expect.toEqual(Some(3))
  })

  test("first/last on a single-element array agree", t => {
    let t_ = ImmutableArray.fromArray([42])
    t->expect(ImmutableArray.first(t_))->Expect.toEqual(Some(42))
    t->expect(ImmutableArray.last(t_))->Expect.toEqual(Some(42))
  })
})

describe("ImmutableArray: every mutating-shaped operation returns a new value", () => {
  test("set does not affect the original", t => {
    let original = ImmutableArray.fromArray([1, 2, 3])
    let updated = ImmutableArray.set(original, 1, 99)
    t->expect(ImmutableArray.toArray(original))->Expect.toEqual([1, 2, 3])
    t->expect(ImmutableArray.toArray(updated))->Expect.toEqual([1, 99, 3])
  })

  test("insertAt does not affect the original", t => {
    let original = ImmutableArray.fromArray([1, 2, 3])
    let updated = ImmutableArray.insertAt(original, 1, 99)
    t->expect(ImmutableArray.toArray(original))->Expect.toEqual([1, 2, 3])
    t->expect(ImmutableArray.toArray(updated))->Expect.toEqual([1, 99, 2, 3])
  })

  test("removeAt does not affect the original", t => {
    let original = ImmutableArray.fromArray([1, 2, 3])
    let updated = ImmutableArray.removeAt(original, 0)
    t->expect(ImmutableArray.toArray(original))->Expect.toEqual([1, 2, 3])
    t->expect(ImmutableArray.toArray(updated))->Expect.toEqual([2, 3])
  })

  test("push appends without affecting the original", t => {
    let original = ImmutableArray.fromArray([1, 2])
    let updated = ImmutableArray.push(original, 3)
    t->expect(ImmutableArray.toArray(original))->Expect.toEqual([1, 2])
    t->expect(ImmutableArray.toArray(updated))->Expect.toEqual([1, 2, 3])
  })

  test("pop removes the last element without affecting the original", t => {
    let original = ImmutableArray.fromArray([1, 2, 3])
    let updated = ImmutableArray.pop(original)
    t->expect(ImmutableArray.toArray(original))->Expect.toEqual([1, 2, 3])
    t->expect(ImmutableArray.toArray(updated))->Expect.toEqual([1, 2])
  })

  test("pop on an empty array is a no-op", t => {
    let t_ = ImmutableArray.make()
    t->expect(ImmutableArray.toArray(ImmutableArray.pop(t_)))->Expect.toEqual([])
  })
})

describe("ImmutableArray: slice/concat", () => {
  test("slice with only start takes everything from there", t => {
    let t_ = ImmutableArray.fromArray([1, 2, 3, 4, 5])
    t->expect(ImmutableArray.toArray(ImmutableArray.slice(t_, ~start=2)))->Expect.toEqual([3, 4, 5])
  })

  test("slice with start and end_ takes exactly that range", t => {
    let t_ = ImmutableArray.fromArray([1, 2, 3, 4, 5])
    t
    ->expect(ImmutableArray.toArray(ImmutableArray.slice(t_, ~start=1, ~end_=3)))
    ->Expect.toEqual([2, 3])
  })

  test("slice clamps an end_ past the length", t => {
    let t_ = ImmutableArray.fromArray([1, 2, 3])
    t
    ->expect(ImmutableArray.toArray(ImmutableArray.slice(t_, ~start=1, ~end_=100)))
    ->Expect.toEqual([2, 3])
  })

  test("slice with start >= end_ is empty", t => {
    let t_ = ImmutableArray.fromArray([1, 2, 3])
    t
    ->expect(ImmutableArray.toArray(ImmutableArray.slice(t_, ~start=2, ~end_=2)))
    ->Expect.toEqual([])
  })

  test("concat joins two arrays in order, without affecting either", t => {
    let left = ImmutableArray.fromArray([1, 2])
    let right = ImmutableArray.fromArray([3, 4])
    let joined = ImmutableArray.concat(left, right)
    t->expect(ImmutableArray.toArray(joined))->Expect.toEqual([1, 2, 3, 4])
    t->expect(ImmutableArray.toArray(left))->Expect.toEqual([1, 2])
    t->expect(ImmutableArray.toArray(right))->Expect.toEqual([3, 4])
  })
})

describe("ImmutableArray: higher-order operations", () => {
  let t_ = ImmutableArray.fromArray([1, 2, 3, 4, 5])

  test("map", t => {
    t
    ->expect(ImmutableArray.toArray(ImmutableArray.map(t_, n => n * 10)))
    ->Expect.toEqual([10, 20, 30, 40, 50])
  })

  test("filter", t => {
    t
    ->expect(ImmutableArray.toArray(ImmutableArray.filter(t_, n => mod(n, 2) == 0)))
    ->Expect.toEqual([2, 4])
  })

  test("reduce", t => {
    t->expect(ImmutableArray.reduce(t_, 0, (acc, n) => acc + n))->Expect.toBe(15)
  })

  test("forEach visits every element in order", t => {
    let visited = []
    ImmutableArray.forEach(t_, n => Array.push(visited, n))
    t->expect(visited)->Expect.toEqual([1, 2, 3, 4, 5])
  })

  test("some / every", t => {
    t->expect(ImmutableArray.some(t_, n => n > 4))->Expect.toBeTruthy
    t->expect(ImmutableArray.some(t_, n => n > 10))->Expect.toBeFalsy
    t->expect(ImmutableArray.every(t_, n => n > 0))->Expect.toBeTruthy
    t->expect(ImmutableArray.every(t_, n => n > 1))->Expect.toBeFalsy
  })

  test("find / findIndex", t => {
    t->expect(ImmutableArray.find(t_, n => n > 3))->Expect.toEqual(Some(4))
    t->expect(ImmutableArray.find(t_, n => n > 10))->Expect.toBeNone
    t->expect(ImmutableArray.findIndex(t_, n => n > 3))->Expect.toEqual(Some(3))
    t->expect(ImmutableArray.findIndex(t_, n => n > 10))->Expect.toBeNone
  })
})

describe("ImmutableArray.equal", () => {
  test("equal arrays compare equal", t => {
    let a = ImmutableArray.fromArray([1, 2, 3])
    let b = ImmutableArray.fromArray([1, 2, 3])
    t->expect(ImmutableArray.equal(a, b, (x, y) => x == y))->Expect.toBeTruthy
  })

  test("different lengths compare unequal", t => {
    let a = ImmutableArray.fromArray([1, 2, 3])
    let b = ImmutableArray.fromArray([1, 2])
    t->expect(ImmutableArray.equal(a, b, (x, y) => x == y))->Expect.toBeFalsy
  })

  test("same length but different elements compare unequal", t => {
    let a = ImmutableArray.fromArray([1, 2, 3])
    let b = ImmutableArray.fromArray([1, 99, 3])
    t->expect(ImmutableArray.equal(a, b, (x, y) => x == y))->Expect.toBeFalsy
  })

  test("two empty arrays compare equal", t => {
    t
    ->expect(
      ImmutableArray.equal(ImmutableArray.make(), ImmutableArray.make(), (x: int, y) => x == y),
    )
    ->Expect.toBeTruthy
  })
})

describe("ImmutableArray: oracle stress test against a plain mutable array", () => {
  test(
    "a long randomized sequence of push/pop/set/insertAt/removeAt matches a mutable reference",
    t => {
      let random = TestSupport.Random.make(777.0)
      let immutable = ref(ImmutableArray.make())
      let oracle = []

      for _ in 1 to 500 {
        let length = Array.length(oracle)
        switch TestSupport.Random.nextInt(random, 5) {
        | 0 =>
          let value = TestSupport.Random.nextInt(random, 1000)
          immutable := ImmutableArray.push(immutable.contents, value)
          Array.push(oracle, value)
        | 1 if length > 0 =>
          immutable := ImmutableArray.pop(immutable.contents)
          let _ = Array.pop(oracle)
        | 2 if length > 0 =>
          let index = TestSupport.Random.nextInt(random, length)
          let value = TestSupport.Random.nextInt(random, 1000)
          immutable := ImmutableArray.set(immutable.contents, index, value)
          oracle[index] = value
        | 3 =>
          let index = TestSupport.Random.nextInt(random, length + 1)
          let value = TestSupport.Random.nextInt(random, 1000)
          immutable := ImmutableArray.insertAt(immutable.contents, index, value)
          oracle->Array.splice(~start=index, ~remove=0, ~insert=[value])
        | 4 if length > 0 =>
          let index = TestSupport.Random.nextInt(random, length)
          immutable := ImmutableArray.removeAt(immutable.contents, index)
          oracle->Array.splice(~start=index, ~remove=1, ~insert=[])
        | _ => () // length == 0 and the op needed a non-empty array: skip this step
        }
        t->expect(ImmutableArray.toArray(immutable.contents))->Expect.toEqual(oracle)
      }
    },
  )
})
