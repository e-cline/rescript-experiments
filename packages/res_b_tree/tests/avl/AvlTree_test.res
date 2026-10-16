/***
Tests `AvlTree` through its public API, mirroring `BTree_test.res`: targeted cases for each
operation, then oracle stress tests that cross-check against `Belt.Map.Int` and run
`checkInvariants` after every single edit.
*/

open Vitest

let id = TestSupport.intId

type tree = AvlTree.t<int, int, TestSupport.IntCmp.identity>

let ascending = (count: int): array<(int, int)> => Belt.Array.makeBy(count, key => (key, key * 10))

describe("AvlTree: construction", () => {
  test("fromArray with an empty array is an empty tree", t => {
    let tree: tree = AvlTree.fromArray(~id, [])
    t->expect(AvlTree.isEmpty(tree))->Expect.toBeTruthy
    AvlTree.checkInvariants(tree)
  })

  test("fromArray keeps the later of two entries with the same key", t => {
    let tree = AvlTree.fromArray(~id, [(2, "b"), (1, "a"), (3, "c"), (1, "a-again")])
    t->expect(AvlTree.size(tree))->Expect.toBe(3)
    t->expect(AvlTree.toArray(tree))->Expect.toEqual([(1, "a-again"), (2, "b"), (3, "c")])
  })

  test("fromArray does not require its input to be pre-sorted", t => {
    let tree = AvlTree.fromArray(~id, [(5, 50), (1, 10), (3, 30), (2, 20), (4, 40)])
    t->expect(AvlTree.keysArray(tree))->Expect.toEqual([1, 2, 3, 4, 5])
    AvlTree.checkInvariants(tree)
  })

  test("fromArray builds a valid tree from already-sorted input, at every small size", t => {
    // Sorted input takes the O(n) balanced-build path rather than repeated `set`.
    for count in 0 to 40 {
      let entries = ascending(count)
      let tree = AvlTree.fromArray(~id, entries)
      AvlTree.checkInvariants(tree)
      t->expect(AvlTree.toArray(tree))->Expect.toEqual(entries)
    }
  })

  test("sorted input with an adjacent duplicate key still keeps the later entry", t => {
    let tree = AvlTree.fromArray(~id, [(1, "a"), (2, "b"), (2, "b-again"), (3, "c")])
    AvlTree.checkInvariants(tree)
    t->expect(AvlTree.toArray(tree))->Expect.toEqual([(1, "a"), (2, "b-again"), (3, "c")])
  })
})

describe("AvlTree: empty tree", () => {
  test("every read operation behaves as expected on an empty tree", t => {
    let tree: tree = AvlTree.make(~id)
    t->expect(AvlTree.size(tree))->Expect.toBe(0)
    t->expect(AvlTree.isEmpty(tree))->Expect.toBeTruthy
    t->expect(AvlTree.get(tree, 1))->Expect.toBeNone
    t->expect(AvlTree.has(tree, 1))->Expect.toBeFalsy
    t->expect(AvlTree.minKey(tree))->Expect.toBeNone
    t->expect(AvlTree.maxKey(tree))->Expect.toBeNone
    t->expect(AvlTree.toArray(tree))->Expect.toEqual([])
    t->expect(AvlTree.keysArray(tree))->Expect.toEqual([])
    t->expect(AvlTree.valuesArray(tree))->Expect.toEqual([])
    t->expect(AvlTree.reduce(tree, 0, (sum, _, value) => sum + value))->Expect.toBe(0)
    AvlTree.checkInvariants(tree)
  })

  test("remove on an empty tree is a no-op, returning the exact same tree", t => {
    let tree: tree = AvlTree.make(~id)
    t->expect(AvlTree.remove(tree, 1) === tree)->Expect.toBeTruthy
  })
})

describe("AvlTree: single-entry tree", () => {
  test("every read operation behaves as expected on a single-entry tree", t => {
    let tree = AvlTree.set(AvlTree.make(~id), 7, 70)
    t->expect(AvlTree.size(tree))->Expect.toBe(1)
    t->expect(AvlTree.isEmpty(tree))->Expect.toBeFalsy
    t->expect(AvlTree.get(tree, 7))->Expect.toEqual(Some(70))
    t->expect(AvlTree.minKey(tree))->Expect.toEqual(Some(7))
    t->expect(AvlTree.maxKey(tree))->Expect.toEqual(Some(7))
    t->expect(AvlTree.toArray(tree))->Expect.toEqual([(7, 70)])
  })

  test("removing the only key empties the tree", t => {
    let tree = AvlTree.remove(AvlTree.set(AvlTree.make(~id), 7, 70), 7)
    t->expect(AvlTree.isEmpty(tree))->Expect.toBeTruthy
    t->expect(AvlTree.size(tree))->Expect.toBe(0)
  })
})

describe("AvlTree: basic get/set/has", () => {
  test("set adds a new key (size increases)", t => {
    let tree = AvlTree.set(AvlTree.fromArray(~id, [(1, 10)]), 2, 20)
    t->expect(AvlTree.size(tree))->Expect.toBe(2)
    t->expect(AvlTree.get(tree, 2))->Expect.toEqual(Some(20))
    t->expect(AvlTree.has(tree, 2))->Expect.toBeTruthy
  })

  test("set overwrites an existing key without changing the size", t => {
    let tree = AvlTree.set(AvlTree.fromArray(~id, [(1, 10), (2, 20)]), 2, 99)
    t->expect(AvlTree.size(tree))->Expect.toBe(2)
    t->expect(AvlTree.get(tree, 2))->Expect.toEqual(Some(99))
  })

  test("set does not modify the tree it was called on", t => {
    let original = AvlTree.fromArray(~id, [(1, 10), (2, 20)])
    let _ = AvlTree.set(original, 3, 30)
    let _ = AvlTree.set(original, 1, 99)
    t->expect(AvlTree.toArray(original))->Expect.toEqual([(1, 10), (2, 20)])
  })

  test("remove does not modify the tree it was called on", t => {
    let original = AvlTree.fromArray(~id, [(1, 10), (2, 20)])
    let _ = AvlTree.remove(original, 1)
    t->expect(AvlTree.toArray(original))->Expect.toEqual([(1, 10), (2, 20)])
  })

  test("setting a key to the value it already holds returns the exact same tree", t => {
    let tree = AvlTree.fromArray(~id, ascending(50))
    t->expect(AvlTree.set(tree, 20, 200) === tree)->Expect.toBeTruthy
    t->expect(AvlTree.set(tree, 20, 201) === tree)->Expect.toBeFalsy
  })

  test("get/has on a missing key", t => {
    let tree = AvlTree.fromArray(~id, [(1, 10), (3, 30)])
    t->expect(AvlTree.get(tree, 2))->Expect.toBeNone
    t->expect(AvlTree.has(tree, 2))->Expect.toBeFalsy
  })

  test("a present key whose value is None is still present", t => {
    let tree = AvlTree.fromArray(~id, [(1, None), (2, Some("two"))])
    t->expect(AvlTree.has(tree, 1))->Expect.toBeTruthy
    t->expect(AvlTree.get(tree, 1))->Expect.toEqual(Some(None))
    t->expect(AvlTree.get(tree, 3))->Expect.toEqual(None)
  })

  test("removing a missing key is a no-op, returning the exact same tree", t => {
    let tree = AvlTree.fromArray(~id, [(1, 10), (3, 30)])
    t->expect(AvlTree.remove(tree, 2) === tree)->Expect.toBeTruthy
    t->expect(AvlTree.remove(tree, 99) === tree)->Expect.toBeTruthy
  })

  test("removing the same key twice: the second removal is a no-op", t => {
    let once = AvlTree.remove(AvlTree.fromArray(~id, [(1, 10), (2, 20)]), 1)
    t->expect(AvlTree.remove(once, 1) === once)->Expect.toBeTruthy
    t->expect(AvlTree.toArray(once))->Expect.toEqual([(2, 20)])
  })
})

describe("AvlTree: ordering", () => {
  let tree = AvlTree.fromArray(~id, [(5, 50), (1, 10), (4, 40), (2, 20), (3, 30)])

  test("toArray/keysArray/valuesArray are sorted by key regardless of insertion order", t => {
    t->expect(AvlTree.toArray(tree))->Expect.toEqual([(1, 10), (2, 20), (3, 30), (4, 40), (5, 50)])
    t->expect(AvlTree.keysArray(tree))->Expect.toEqual([1, 2, 3, 4, 5])
    t->expect(AvlTree.valuesArray(tree))->Expect.toEqual([10, 20, 30, 40, 50])
    t->expect(AvlTree.minKey(tree))->Expect.toEqual(Some(1))
    t->expect(AvlTree.maxKey(tree))->Expect.toEqual(Some(5))
  })

  test("forEach and reduce visit entries in ascending key order", t => {
    let visited = []
    AvlTree.forEach(tree, (key, value) => Array.push(visited, (key, value)))
    t->expect(visited)->Expect.toEqual(AvlTree.toArray(tree))
    t
    ->expect(AvlTree.reduce(tree, "", (text, key, _) => text ++ Int.toString(key)))
    ->Expect.toBe("12345")
  })
})

describe("AvlTree: order statistics (getAt / indexOf)", () => {
  test("getAt and indexOf on an empty tree always return None", t => {
    let tree: tree = AvlTree.make(~id)
    t->expect(AvlTree.getAt(tree, 0))->Expect.toBeNone
    t->expect(AvlTree.getAt(tree, -1))->Expect.toBeNone
    t->expect(AvlTree.indexOf(tree, 0))->Expect.toBeNone
  })

  test("getAt is out of range below 0 or at/above size, in range everywhere between", t => {
    let tree = AvlTree.fromArray(~id, ascending(10))
    t->expect(AvlTree.getAt(tree, -1))->Expect.toBeNone
    t->expect(AvlTree.getAt(tree, 10))->Expect.toBeNone
    t->expect(AvlTree.getAt(tree, 0))->Expect.toEqual(Some((0, 0)))
    t->expect(AvlTree.getAt(tree, 9))->Expect.toEqual(Some((9, 90)))
  })

  test("indexOf returns the position of a present key, None for an absent one", t => {
    let tree = AvlTree.fromArray(~id, [(30, 0), (10, 0), (20, 0)])
    t->expect(AvlTree.indexOf(tree, 10))->Expect.toEqual(Some(0))
    t->expect(AvlTree.indexOf(tree, 20))->Expect.toEqual(Some(1))
    t->expect(AvlTree.indexOf(tree, 30))->Expect.toEqual(Some(2))
    t->expect(AvlTree.indexOf(tree, 15))->Expect.toBeNone
  })
})

/**
Checks `getAt`/`indexOf` at every position against the oracle's sorted entries, plus one
position off each end.
*/
let // Each check compares a whole array in one `expect`: the stress tests below
// call this after every step, and an `expect` per entry made them slow enough
// to time out on CI.
checkOrderStatistics = (t, tree: tree, oracleArray: array<(int, int)>) => {
  t
  ->expect(oracleArray->Array.mapWithIndex((_, index) => AvlTree.getAt(tree, index)))
  ->Expect.toEqual(oracleArray->Array.map(entry => Some(entry)))
  t
  ->expect(oracleArray->Array.map(((key, _)) => AvlTree.indexOf(tree, key)))
  ->Expect.toEqual(oracleArray->Array.mapWithIndex((_, index) => Some(index)))
  t->expect(AvlTree.getAt(tree, -1))->Expect.toBeNone
  t->expect(AvlTree.getAt(tree, Array.length(oracleArray)))->Expect.toBeNone
}

describe("AvlTree: rebalancing", () => {
  test("ascending, descending, and zig-zag insertion orders all stay balanced", t => {
    let orders = [
      Belt.Array.makeBy(300, index => index),
      Belt.Array.makeBy(300, index => 299 - index),
      Belt.Array.makeBy(300, index => mod(index, 2) == 0 ? index / 2 : 299 - index / 2),
    ]
    orders->Array.forEach(
      order => {
        let tree = ref(AvlTree.make(~id))
        order->Array.forEach(
          key => {
            tree := AvlTree.set(tree.contents, key, key)
            AvlTree.checkInvariants(tree.contents)
          },
        )
        t->expect(AvlTree.keysArray(tree.contents))->Expect.toEqual(Belt.Array.makeBy(300, i => i))
      },
    )
  })

  test("removing from one end, the other, and the middle all stay balanced", t => {
    let orders = [
      Belt.Array.makeBy(300, index => index),
      Belt.Array.makeBy(300, index => 299 - index),
      // The root's own key, repeatedly: always a node with two children until the very end.
      Belt.Array.makeBy(300, index => mod(index, 2) == 0 ? 150 + index / 2 : 149 - index / 2),
    ]
    orders->Array.forEach(
      order => {
        let tree = ref(AvlTree.fromArray(~id, ascending(300)))
        order->Array.forEachWithIndex(
          (key, index) => {
            tree := AvlTree.remove(tree.contents, key)
            AvlTree.checkInvariants(tree.contents)
            t->expect(AvlTree.size(tree.contents))->Expect.toBe(299 - index)
            t->expect(AvlTree.has(tree.contents, key))->Expect.toBeFalsy
          },
        )
        t->expect(AvlTree.isEmpty(tree.contents))->Expect.toBeTruthy
      },
    )
  })
})

describe("AvlTree: oracle stress tests (cross-checked against Belt.Map.Int)", () => {
  test("random insert/remove order matches a plain sorted map at every checkpoint", t => {
    let random = TestSupport.Random.make(20240521.0)
    let entryCount = 400
    let insertOrder = TestSupport.Random.shuffledRange(random, entryCount)
    let removeOrder = TestSupport.Random.shuffledRange(random, entryCount)

    let tree = ref(AvlTree.make(~id))
    let oracle = ref(Belt.Map.Int.empty)

    Belt.Array.forEach(
      insertOrder,
      key => {
        tree := AvlTree.set(tree.contents, key, key * 10)
        oracle := Belt.Map.Int.set(oracle.contents, key, key * 10)
        AvlTree.checkInvariants(tree.contents)
      },
    )
    t->expect(AvlTree.size(tree.contents))->Expect.toBe(Belt.Map.Int.size(oracle.contents))
    t->expect(AvlTree.toArray(tree.contents))->Expect.toEqual(Belt.Map.Int.toArray(oracle.contents))
    checkOrderStatistics(t, tree.contents, Belt.Map.Int.toArray(oracle.contents))

    // Remove two-thirds of the keys, in a different shuffled order.
    let removeCount = entryCount * 2 / 3
    Belt.Array.forEach(
      removeOrder->Belt.Array.slice(~offset=0, ~len=removeCount),
      key => {
        tree := AvlTree.remove(tree.contents, key)
        oracle := Belt.Map.Int.remove(oracle.contents, key)
        AvlTree.checkInvariants(tree.contents)
      },
    )
    t->expect(AvlTree.size(tree.contents))->Expect.toBe(Belt.Map.Int.size(oracle.contents))
    t->expect(AvlTree.toArray(tree.contents))->Expect.toEqual(Belt.Map.Int.toArray(oracle.contents))
    checkOrderStatistics(t, tree.contents, Belt.Map.Int.toArray(oracle.contents))

    // Remove the rest; both should end up empty together.
    Belt.Array.forEach(
      removeOrder->Belt.Array.slice(~offset=removeCount, ~len=entryCount - removeCount),
      key => {
        tree := AvlTree.remove(tree.contents, key)
        oracle := Belt.Map.Int.remove(oracle.contents, key)
        AvlTree.checkInvariants(tree.contents)
      },
    )
    t->expect(AvlTree.isEmpty(tree.contents))->Expect.toBeTruthy
    t->expect(Belt.Map.Int.isEmpty(oracle.contents))->Expect.toBeTruthy
    t->expect(AvlTree.getAt(tree.contents, 0))->Expect.toBeNone
  })

  test(
    "a long interleaved sequence of random inserts, overwrites, and removals matches a plain sorted map at every step",
    t => {
      let random = TestSupport.Random.make(998877.0)
      let tree = ref(AvlTree.make(~id))
      let oracle = ref(Belt.Map.Int.empty)
      // A key space small relative to the step count, so removals of absent keys and
      // overwrites of present ones both happen often, alongside real insertions and removals.
      let keySpace = 60
      for step in 0 to 1999 {
        let key = TestSupport.Random.nextInt(random, keySpace)
        if mod(step, 3) == 0 {
          tree := AvlTree.remove(tree.contents, key)
          oracle := Belt.Map.Int.remove(oracle.contents, key)
        } else {
          tree := AvlTree.set(tree.contents, key, step)
          oracle := Belt.Map.Int.set(oracle.contents, key, step)
        }
        AvlTree.checkInvariants(tree.contents)
        let oracleArray = Belt.Map.Int.toArray(oracle.contents)
        t->expect(AvlTree.size(tree.contents))->Expect.toBe(Belt.Map.Int.size(oracle.contents))
        t->expect(AvlTree.toArray(tree.contents))->Expect.toEqual(oracleArray)
        t
        ->expect(AvlTree.keysArray(tree.contents))
        ->Expect.toEqual(oracleArray->Array.map(Pair.first))
        t
        ->expect(AvlTree.valuesArray(tree.contents))
        ->Expect.toEqual(oracleArray->Array.map(Pair.second))
        t
        ->expect(AvlTree.get(tree.contents, key))
        ->Expect.toEqual(Belt.Map.Int.get(oracle.contents, key))
        checkOrderStatistics(t, tree.contents, oracleArray)
      }
    },
  )
})
