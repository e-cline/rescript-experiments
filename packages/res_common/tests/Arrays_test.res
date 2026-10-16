open Vitest

let intCompare = (a: int, b: int): int => a - b

describe("Arrays.insertAt / removeAt / replaceAt", () => {
  test("insertAt shifts everything at or after the index right", t => {
    t->expect(Arrays.insertAt([1, 2, 3], 1, 99))->Expect.toEqual([1, 99, 2, 3])
  })
  test("insertAt at the front", t => {
    t->expect(Arrays.insertAt([1, 2, 3], 0, 99))->Expect.toEqual([99, 1, 2, 3])
  })
  test("insertAt at the end", t => {
    t->expect(Arrays.insertAt([1, 2, 3], 3, 99))->Expect.toEqual([1, 2, 3, 99])
  })
  test("insertAt into an empty array", t => {
    t->expect(Arrays.insertAt([], 0, 99))->Expect.toEqual([99])
  })

  test("removeAt removes exactly the element at the index", t => {
    t->expect(Arrays.removeAt([1, 2, 3], 1))->Expect.toEqual([1, 3])
  })
  test("removeAt the first element", t => {
    t->expect(Arrays.removeAt([1, 2, 3], 0))->Expect.toEqual([2, 3])
  })
  test("removeAt the last element", t => {
    t->expect(Arrays.removeAt([1, 2, 3], 2))->Expect.toEqual([1, 2])
  })
  test("removeAt a single-element array leaves it empty", t => {
    t->expect(Arrays.removeAt([1], 0))->Expect.toEqual([])
  })

  test("replaceAt replaces exactly the element at the index", t => {
    t->expect(Arrays.replaceAt([1, 2, 3], 1, 99))->Expect.toEqual([1, 99, 3])
  })
  test("replaceAt does not mutate the original array", t => {
    let original = [1, 2, 3]
    let _ = Arrays.replaceAt(original, 1, 99)
    t->expect(original)->Expect.toEqual([1, 2, 3])
  })
})

describe("Arrays.chunk", () => {
  test("splits evenly-divisible arrays into equal chunks", t => {
    t->expect(Arrays.chunk([1, 2, 3, 4, 5, 6], 2))->Expect.toEqual([[1, 2], [3, 4], [5, 6]])
  })
  test("the final chunk holds the remainder", t => {
    t->expect(Arrays.chunk([1, 2, 3, 4, 5], 2))->Expect.toEqual([[1, 2], [3, 4], [5]])
  })
  test("a chunk size larger than the array yields one chunk", t => {
    t->expect(Arrays.chunk([1, 2], 10))->Expect.toEqual([[1, 2]])
  })
  test("an empty array yields no chunks", t => {
    t->expect(Arrays.chunk([], 3))->Expect.toEqual([])
  })
  test("size 1 yields one chunk per element", t => {
    t->expect(Arrays.chunk([1, 2, 3], 1))->Expect.toEqual([[1], [2], [3]])
  })
})

describe("Arrays.zip / zipWith", () => {
  test("zip pairs elements up to the shorter length", t => {
    t->expect(Arrays.zip([1, 2, 3], ["a", "b"]))->Expect.toEqual([(1, "a"), (2, "b")])
  })
  test("zip with an empty array yields an empty array", t => {
    t->expect(Arrays.zip([1, 2], []))->Expect.toEqual([])
  })
  test("zipWith combines pairs with the given function", t => {
    t
    ->expect(Arrays.zipWith([1, 2, 3], [10, 20, 30], (a, b) => a + b))
    ->Expect.toEqual([11, 22, 33])
  })
})

describe("Arrays.partition", () => {
  test("splits into matching and non-matching, preserving order", t => {
    let (evens, odds) = Arrays.partition([1, 2, 3, 4, 5, 6], n => mod(n, 2) == 0)
    t->expect(evens)->Expect.toEqual([2, 4, 6])
    t->expect(odds)->Expect.toEqual([1, 3, 5])
  })
  test("an empty array partitions into two empty arrays", t => {
    let (matched, unmatched) = Arrays.partition([], (_: int) => true)
    t->expect(matched)->Expect.toEqual([])
    t->expect(unmatched)->Expect.toEqual([])
  })
  test("everything matching leaves the second array empty", t => {
    let (matched, unmatched) = Arrays.partition([1, 2, 3], _ => true)
    t->expect(matched)->Expect.toEqual([1, 2, 3])
    t->expect(unmatched)->Expect.toEqual([])
  })
})

describe("Arrays.groupBy", () => {
  test("groups elements by their computed key, preserving relative order", t => {
    let groups = Arrays.groupBy([1, 2, 3, 4, 5, 6], n => mod(n, 2) == 0 ? "even" : "odd")
    t->expect(groups->Belt.Map.String.get("even"))->Expect.toEqual(Some([2, 4, 6]))
    t->expect(groups->Belt.Map.String.get("odd"))->Expect.toEqual(Some([1, 3, 5]))
  })
  test("an empty array groups into an empty map", t => {
    let groups = Arrays.groupBy([], (n: int) => Int.toString(n))
    t->expect(groups->Belt.Map.String.size)->Expect.toBe(0)
  })
})

describe("Arrays.uniqueBy", () => {
  test("keeps only the first occurrence of each key, in order", t => {
    t
    ->expect(Arrays.uniqueBy([1, 2, 2, 3, 1, 4], n => Int.toString(n)))
    ->Expect.toEqual([1, 2, 3, 4])
  })
  test("an array with no duplicates is unchanged", t => {
    t->expect(Arrays.uniqueBy([1, 2, 3], n => Int.toString(n)))->Expect.toEqual([1, 2, 3])
  })
  test("an empty array stays empty", t => {
    t->expect(Arrays.uniqueBy([], (n: int) => Int.toString(n)))->Expect.toEqual([])
  })
})

describe("Arrays.flatten", () => {
  test("flattens one level of nesting, preserving order", t => {
    t->expect(Arrays.flatten([[1, 2], [3], [4, 5]]))->Expect.toEqual([1, 2, 3, 4, 5])
  })
  test("flattens away empty inner arrays", t => {
    t->expect(Arrays.flatten([[1], [], [2]]))->Expect.toEqual([1, 2])
  })
  test("an empty outer array flattens to empty", t => {
    t->expect(Arrays.flatten([]))->Expect.toEqual([])
  })
})

describe("Arrays.bisectLeft / bisectRight", () => {
  let sorted = [1, 3, 3, 3, 5, 7]

  test("bisectLeft finds the leftmost insertion point for a present value", t => {
    t->expect(Arrays.bisectLeft(sorted, 3, ~compare=intCompare))->Expect.toBe(1)
  })
  test("bisectRight finds the rightmost insertion point for a present value", t => {
    t->expect(Arrays.bisectRight(sorted, 3, ~compare=intCompare))->Expect.toBe(4)
  })
  test("bisectLeft/bisectRight agree on a value absent from the array", t => {
    t->expect(Arrays.bisectLeft(sorted, 4, ~compare=intCompare))->Expect.toBe(4)
    t->expect(Arrays.bisectRight(sorted, 4, ~compare=intCompare))->Expect.toBe(4)
  })
  test("a value smaller than everything inserts at 0", t => {
    t->expect(Arrays.bisectLeft(sorted, 0, ~compare=intCompare))->Expect.toBe(0)
    t->expect(Arrays.bisectRight(sorted, 0, ~compare=intCompare))->Expect.toBe(0)
  })
  test("a value larger than everything inserts at the end", t => {
    t->expect(Arrays.bisectLeft(sorted, 8, ~compare=intCompare))->Expect.toBe(6)
    t->expect(Arrays.bisectRight(sorted, 8, ~compare=intCompare))->Expect.toBe(6)
  })
  test("an empty array always inserts at 0", t => {
    t->expect(Arrays.bisectLeft([], 5, ~compare=intCompare))->Expect.toBe(0)
    t->expect(Arrays.bisectRight([], 5, ~compare=intCompare))->Expect.toBe(0)
  })
  test("respects explicit lo/hi bounds", t => {
    // Restrict the search to `[2, 5)` -- indices 2..4, values [3, 3, 5] --
    // so a value that appears outside the window is treated as absent.
    t->expect(Arrays.bisectLeft(sorted, 1, ~compare=intCompare, ~lo=2, ~hi=5))->Expect.toBe(2)
  })

  test("oracle: agrees with a linear scan across many random arrays", t => {
    let random = TestSupport.Random.make(12345.0)
    for _ in 1 to 200 {
      let length = TestSupport.Random.nextInt(random, 30)
      let array =
        Belt.Array.makeBy(
          length,
          _ => TestSupport.Random.nextInt(random, 10),
        )->Belt.SortArray.stableSortBy(intCompare)
      let value = TestSupport.Random.nextInt(random, 10)

      let linearLeft = ref(0)
      while (
        linearLeft.contents < Array.length(array) &&
          Array.getUnsafe(array, linearLeft.contents) < value
      ) {
        linearLeft := linearLeft.contents + 1
      }
      let linearRight = ref(linearLeft.contents)
      while (
        linearRight.contents < Array.length(array) &&
          Array.getUnsafe(array, linearRight.contents) == value
      ) {
        linearRight := linearRight.contents + 1
      }

      t
      ->expect(Arrays.bisectLeft(array, value, ~compare=intCompare))
      ->Expect.toBe(linearLeft.contents)
      t
      ->expect(Arrays.bisectRight(array, value, ~compare=intCompare))
      ->Expect.toBe(linearRight.contents)
    }
  })
})
