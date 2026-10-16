open Vitest

describe("Sequence: construction and basic access", () => {
  test("empty is empty", t => {
    t->expect(Sequence.isEmpty(Sequence.empty()))->Expect.toBeTruthy
    t->expect(Sequence.uncons(Sequence.empty()))->Expect.toBeNone
  })

  test("singleton yields exactly one value", t => {
    let s = Sequence.singleton(42)
    t->expect(Sequence.toArray(s))->Expect.toEqual([42])
  })

  test("cons prepends a value", t => {
    let s = Sequence.cons(1, Sequence.fromArray([2, 3]))
    t->expect(Sequence.toArray(s))->Expect.toEqual([1, 2, 3])
  })

  test("fromArray/toArray round-trips, including the empty array", t => {
    t->expect(Sequence.toArray(Sequence.fromArray([1, 2, 3])))->Expect.toEqual([1, 2, 3])
    t->expect(Sequence.toArray(Sequence.fromArray([])))->Expect.toEqual([])
  })

  test("uncons splits the sequence into its head and the rest", t => {
    let s = Sequence.fromArray([1, 2, 3])
    switch Sequence.uncons(s) {
    | None => t->expect(true)->Expect.toBeFalsy
    | Some((head, rest)) => {
        t->expect(head)->Expect.toBe(1)
        t->expect(Sequence.toArray(rest))->Expect.toEqual([2, 3])
      }
    }
  })
})

describe("Sequence: map/filter/take/drop/takeWhile/append/zip", () => {
  let s = Sequence.fromArray([1, 2, 3, 4, 5])

  test("map", t => {
    t->expect(Sequence.toArray(Sequence.map(s, n => n * 10)))->Expect.toEqual([10, 20, 30, 40, 50])
  })

  test("filter", t => {
    t
    ->expect(Sequence.toArray(Sequence.filter(s, n => mod(n, 2) == 0)))
    ->Expect.toEqual([2, 4])
  })

  test("take fewer than the length", t => {
    t->expect(Sequence.toArray(Sequence.take(s, 3)))->Expect.toEqual([1, 2, 3])
  })

  test("take more than the length stops at the end", t => {
    t->expect(Sequence.toArray(Sequence.take(s, 100)))->Expect.toEqual([1, 2, 3, 4, 5])
  })

  test("take 0 is empty", t => {
    t->expect(Sequence.toArray(Sequence.take(s, 0)))->Expect.toEqual([])
  })

  test("drop fewer than the length", t => {
    t->expect(Sequence.toArray(Sequence.drop(s, 2)))->Expect.toEqual([3, 4, 5])
  })

  test("drop more than the length is empty", t => {
    t->expect(Sequence.toArray(Sequence.drop(s, 100)))->Expect.toEqual([])
  })

  test("drop 0 is unchanged", t => {
    t->expect(Sequence.toArray(Sequence.drop(s, 0)))->Expect.toEqual([1, 2, 3, 4, 5])
  })

  test("takeWhile stops at the first non-matching element", t => {
    t->expect(Sequence.toArray(Sequence.takeWhile(s, n => n < 3)))->Expect.toEqual([1, 2])
  })

  test("takeWhile matching nothing is empty", t => {
    t->expect(Sequence.toArray(Sequence.takeWhile(s, n => n > 100)))->Expect.toEqual([])
  })

  test("takeWhile matching everything is the whole sequence", t => {
    t->expect(Sequence.toArray(Sequence.takeWhile(s, _ => true)))->Expect.toEqual([1, 2, 3, 4, 5])
  })

  test("append joins two sequences in order", t => {
    t
    ->expect(
      Sequence.toArray(Sequence.append(Sequence.fromArray([1, 2]), Sequence.fromArray([3, 4]))),
    )
    ->Expect.toEqual([1, 2, 3, 4])
  })

  test("append with an empty sequence on either side", t => {
    t
    ->expect(Sequence.toArray(Sequence.append(Sequence.empty(), Sequence.fromArray([1, 2]))))
    ->Expect.toEqual([1, 2])
    t
    ->expect(Sequence.toArray(Sequence.append(Sequence.fromArray([1, 2]), Sequence.empty())))
    ->Expect.toEqual([1, 2])
  })

  test("zip stops at the shorter sequence", t => {
    t
    ->expect(
      Sequence.toArray(Sequence.zip(Sequence.fromArray([1, 2, 3]), Sequence.fromArray(["a", "b"]))),
    )
    ->Expect.toEqual([(1, "a"), (2, "b")])
  })

  test("pipelines compose without forcing anything until the end", t => {
    t
    ->expect(
      s
      ->Sequence.filter(n => mod(n, 2) == 1)
      ->Sequence.map(n => n * 100)
      ->Sequence.take(2)
      ->Sequence.toArray,
    )
    ->Expect.toEqual([100, 300])
  })
})

describe("Sequence: forEach/reduce/length", () => {
  let s = Sequence.fromArray([1, 2, 3, 4, 5])

  test("forEach visits every element in order", t => {
    let visited = []
    Sequence.forEach(s, n => Array.push(visited, n))
    t->expect(visited)->Expect.toEqual([1, 2, 3, 4, 5])
  })

  test("reduce folds left to right", t => {
    t->expect(Sequence.reduce(s, 0, (acc, n) => acc + n))->Expect.toBe(15)
    t
    ->expect(Sequence.reduce(s, "", (acc, n) => acc ++ Int.toString(n)))
    ->Expect.toBe("12345")
  })

  test("length counts every element", t => {
    t->expect(Sequence.length(s))->Expect.toBe(5)
    t->expect(Sequence.length(Sequence.empty()))->Expect.toBe(0)
  })
})

describe("Sequence: infinite sequences (iterate/repeat) stay lazy", () => {
  test("iterate produces the expected prefix without ever finishing", t => {
    let powersOfTwo = Sequence.iterate(1, n => n * 2)
    t->expect(Sequence.toArray(Sequence.take(powersOfTwo, 6)))->Expect.toEqual([1, 2, 4, 8, 16, 32])
  })

  test("repeat produces the same value forever, truncated by take", t => {
    let allSevens = Sequence.repeat(7)
    t->expect(Sequence.toArray(Sequence.take(allSevens, 4)))->Expect.toEqual([7, 7, 7, 7])
  })

  test("filter over an infinite sequence, truncated by take, still terminates", t => {
    let evens = Sequence.iterate(0, n => n + 1)->Sequence.filter(n => mod(n, 2) == 0)
    t->expect(Sequence.toArray(Sequence.take(evens, 5)))->Expect.toEqual([0, 2, 4, 6, 8])
  })

  test("dropping a finite prefix of an infinite sequence, then taking, terminates", t => {
    let naturals = Sequence.iterate(0, n => n + 1)
    t
    ->expect(Sequence.toArray(Sequence.take(Sequence.drop(naturals, 1000), 3)))
    ->Expect.toEqual([1000, 1001, 1002])
  })
})

describe("Sequence: genuine laziness (elements aren't computed until forced)", () => {
  test("map's function is not called for elements beyond what take actually consumes", t => {
    let calls = ref(0)
    let result =
      Sequence.fromArray([1, 2, 3, 4, 5])
      ->Sequence.map(
        n => {
          calls := calls.contents + 1
          n * 2
        },
      )
      ->Sequence.take(2)
      ->Sequence.toArray
    t->expect(result)->Expect.toEqual([2, 4])
    t->expect(calls.contents)->Expect.toBe(2)
  })

  test("an infinite iterate's generator function is only called as many times as consumed", t => {
    let calls = ref(0)
    let s = Sequence.iterate(
      0,
      n => {
        calls := calls.contents + 1
        n + 1
      },
    )
    let _ = Sequence.toArray(Sequence.take(s, 5))
    // `iterate(seed, f)` calls `f` once per element *after* the seed, so
    // 5 elements (the seed plus 4 more) means exactly 4 calls.
    t->expect(calls.contents)->Expect.toBe(4)
  })

  test("building a pipeline does no work at all until it's forced", t => {
    let calls = ref(0)
    let _pipeline =
      Sequence.fromArray([1, 2, 3])
      ->Sequence.map(
        n => {
          calls := calls.contents + 1
          n
        },
      )
      ->Sequence.filter(n => n > 0)
      ->Sequence.take(2)
    t->expect(calls.contents)->Expect.toBe(0)
  })
})

describe("Sequence: oracle stress test against Array combinators", () => {
  test("map/filter/take/reduce agree with their plain-Array equivalents", t => {
    let random = TestSupport.Random.make(555.0)
    for _ in 1 to 100 {
      let length = TestSupport.Random.nextInt(random, 50)
      let array = Belt.Array.makeBy(length, _ => TestSupport.Random.nextInt(random, 100))
      let takeCount = TestSupport.Random.nextInt(random, length + 5)

      let expected =
        array
        ->Array.filter(n => mod(n, 2) == 0)
        ->Array.map(n => n + 1)
        ->Belt.Array.slice(~offset=0, ~len=takeCount)

      let actual =
        Sequence.fromArray(array)
        ->Sequence.filter(n => mod(n, 2) == 0)
        ->Sequence.map(n => n + 1)
        ->Sequence.take(takeCount)
        ->Sequence.toArray

      t->expect(actual)->Expect.toEqual(expected)
    }
  })
})
