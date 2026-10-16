/***
Written directly in ReScript, using rescript-vitest's bindings to
Vitest's own `describe`/`test`/`expect` API -- see
the res_trees README for why this is named `BTree_test.res`, not
`b_tree.test.res`.
*/

open Vitest

let id = TestSupport.intId

describe("BTree: construction", () => {
  test("make defaults to a maxNodeSize of 32", t => {
    t->expect(BTree.maxNodeSize(BTree.make(~id)))->Expect.toBe(32)
  })

  test("make accepts a custom maxNodeSize", t => {
    t->expect(BTree.maxNodeSize(BTree.make(~id, ~maxNodeSize=100)))->Expect.toBe(100)
  })

  test("make clamps maxNodeSize below 4 up to the default of 32", t => {
    t->expect(BTree.maxNodeSize(BTree.make(~id, ~maxNodeSize=1)))->Expect.toBe(32)
    t->expect(BTree.maxNodeSize(BTree.make(~id, ~maxNodeSize=0)))->Expect.toBe(32)
    t->expect(BTree.maxNodeSize(BTree.make(~id, ~maxNodeSize=-5)))->Expect.toBe(32)
  })

  test("make clamps maxNodeSize above 256 down to 256", t => {
    t->expect(BTree.maxNodeSize(BTree.make(~id, ~maxNodeSize=10000)))->Expect.toBe(256)
  })

  test("make accepts the boundary values 4 and 256 unclamped", t => {
    t->expect(BTree.maxNodeSize(BTree.make(~id, ~maxNodeSize=4)))->Expect.toBe(4)
    t->expect(BTree.maxNodeSize(BTree.make(~id, ~maxNodeSize=256)))->Expect.toBe(256)
  })

  test("fromArray with an empty array is an empty tree", t => {
    let tree = BTree.fromArray(~id, [])
    t->expect(BTree.isEmpty(tree))->Expect.toBeTruthy
  })

  test(
    "fromArray with duplicate keys keeps the later pair, matching set's overwrite behavior",
    t => {
      let tree = BTree.fromArray(~id, [(1, "first"), (2, "b"), (1, "second")])
      t->expect(BTree.size(tree))->Expect.toBe(2)
      t->expect(BTree.get(tree, 1))->Expect.toEqual(Some("second"))
    },
  )

  test("fromArray does not require its input to be pre-sorted", t => {
    let tree = BTree.fromArray(~id, [(3, "c"), (1, "a"), (2, "b")])
    t->expect(BTree.toArray(tree))->Expect.toEqual([(1, "a"), (2, "b"), (3, "c")])
  })
})

describe("BTree: empty tree", () => {
  test("every read operation behaves as expected on an empty tree", t => {
    let tree = BTree.make(~id)
    t->expect(BTree.size(tree))->Expect.toBe(0)
    t->expect(BTree.isEmpty(tree))->Expect.toBeTruthy
    t->expect(BTree.get(tree, 1))->Expect.toBeNone
    t->expect(BTree.has(tree, 1))->Expect.toBeFalsy
    t->expect(BTree.minKey(tree))->Expect.toBeNone
    t->expect(BTree.maxKey(tree))->Expect.toBeNone
    t->expect(BTree.toArray(tree))->Expect.toEqual([])
    t->expect(BTree.keysArray(tree))->Expect.toEqual([])
    t->expect(BTree.valuesArray(tree))->Expect.toEqual([])
    t->expect(BTree.reduce(tree, 0, (accumulator, _, _) => accumulator + 1))->Expect.toBe(0)

    let visited = ref(0)
    BTree.forEach(tree, (_, _) => visited := visited.contents + 1)
    t->expect(visited.contents)->Expect.toBe(0)
  })

  test("remove on an empty tree is a no-op, returning the exact same tree", t => {
    let tree = BTree.make(~id)
    let result = BTree.remove(tree, 1)
    t->expect(result === tree)->Expect.toBeTruthy
  })

  test("checkInvariants passes trivially on an empty tree", t => {
    BTree.checkInvariants(BTree.make(~id))
    t->expect(true)->Expect.toBeTruthy
  })
})

describe("BTree: single-entry tree", () => {
  test("every read operation behaves as expected on a single-entry tree", t => {
    let tree = BTree.make(~id)->BTree.set(1, "one")
    t->expect(BTree.size(tree))->Expect.toBe(1)
    t->expect(BTree.isEmpty(tree))->Expect.toBeFalsy
    t->expect(BTree.get(tree, 1))->Expect.toEqual(Some("one"))
    t->expect(BTree.has(tree, 1))->Expect.toBeTruthy
    t->expect(BTree.minKey(tree))->Expect.toEqual(Some(1))
    t->expect(BTree.maxKey(tree))->Expect.toEqual(Some(1))
    t->expect(BTree.toArray(tree))->Expect.toEqual([(1, "one")])
  })

  test("removing the only key empties the tree", t => {
    let tree = BTree.make(~id)->BTree.set(1, "one")->BTree.remove(1)
    t->expect(BTree.isEmpty(tree))->Expect.toBeTruthy
    t->expect(BTree.get(tree, 1))->Expect.toBeNone
  })
})

describe("BTree: basic get/set/has", () => {
  test("set adds a new key and reports it as new (size increases)", t => {
    let tree = BTree.make(~id)->BTree.set(1, "one")
    t->expect(BTree.size(tree))->Expect.toBe(1)
    t->expect(BTree.get(tree, 1))->Expect.toEqual(Some("one"))
    t->expect(BTree.has(tree, 1))->Expect.toBeTruthy
  })

  test("set overwrites an existing key without changing the size", t => {
    let tree = BTree.make(~id)->BTree.set(1, "one")->BTree.set(1, "uno")
    t->expect(BTree.size(tree))->Expect.toBe(1)
    t->expect(BTree.get(tree, 1))->Expect.toEqual(Some("uno"))
  })

  test("set does not modify the tree it was called on", t => {
    let original = BTree.make(~id)->BTree.set(1, "one")
    let _ = BTree.set(original, 2, "two")
    t->expect(BTree.size(original))->Expect.toBe(1)
    t->expect(BTree.get(original, 2))->Expect.toBeNone
  })

  test("remove does not modify the tree it was called on", t => {
    let original = BTree.make(~id)->BTree.set(1, "one")->BTree.set(2, "two")
    let _ = BTree.remove(original, 1)
    t->expect(BTree.size(original))->Expect.toBe(2)
    t->expect(BTree.get(original, 1))->Expect.toEqual(Some("one"))
  })

  test("get on a missing key returns None", t => {
    let tree = BTree.make(~id)->BTree.set(1, "one")
    t->expect(BTree.get(tree, 2))->Expect.toBeNone
  })

  test("removing a missing key is a no-op, returning the exact same tree", t => {
    let tree = BTree.make(~id)->BTree.set(1, "one")
    let result = BTree.remove(tree, 2)
    t->expect(result === tree)->Expect.toBeTruthy
  })

  test("removing the same key twice: the second removal is a no-op", t => {
    let tree = BTree.make(~id)->BTree.set(1, "one")->BTree.set(2, "two")
    let onceRemoved = BTree.remove(tree, 1)
    let twiceRemoved = BTree.remove(onceRemoved, 1)
    t->expect(twiceRemoved === onceRemoved)->Expect.toBeTruthy
  })
})

describe("BTree: ordering", () => {
  test("toArray/keysArray/valuesArray are sorted by key regardless of insertion order", t => {
    let tree =
      BTree.make(~id)
      ->BTree.set(5, "e")
      ->BTree.set(1, "a")
      ->BTree.set(3, "c")
      ->BTree.set(4, "d")
      ->BTree.set(2, "b")
    t
    ->expect(BTree.toArray(tree))
    ->Expect.toEqual([(1, "a"), (2, "b"), (3, "c"), (4, "d"), (5, "e")])
    t->expect(BTree.keysArray(tree))->Expect.toEqual([1, 2, 3, 4, 5])
    t->expect(BTree.valuesArray(tree))->Expect.toEqual(["a", "b", "c", "d", "e"])
    t->expect(BTree.minKey(tree))->Expect.toEqual(Some(1))
    t->expect(BTree.maxKey(tree))->Expect.toEqual(Some(5))
  })

  test("forEach and reduce visit entries in ascending key order", t => {
    let tree = BTree.make(~id)->BTree.set(3, 30)->BTree.set(1, 10)->BTree.set(2, 20)
    let visited = []
    BTree.forEach(tree, (key, value) => Array.push(visited, (key, value)))
    t->expect(visited)->Expect.toEqual([(1, 10), (2, 20), (3, 30)])

    let sum = BTree.reduce(tree, 0, (accumulator, _key, value) => accumulator + value)
    t->expect(sum)->Expect.toBe(60)
  })
})

describe("BTree: order statistics (getAt / indexOf)", () => {
  test("getAt and indexOf on an empty tree always return None", t => {
    let tree = BTree.make(~id)
    t->expect(BTree.getAt(tree, 0))->Expect.toBeNone
    t->expect(BTree.getAt(tree, -1))->Expect.toBeNone
    t->expect(BTree.indexOf(tree, 1))->Expect.toBeNone
  })

  test("getAt is out of range below 0 or at/above size, in range everywhere between", t => {
    let tree = BTree.fromArray(~id, [(1, "a"), (2, "b"), (3, "c")])
    t->expect(BTree.getAt(tree, -1))->Expect.toBeNone
    t->expect(BTree.getAt(tree, -100))->Expect.toBeNone
    t->expect(BTree.getAt(tree, 3))->Expect.toBeNone
    t->expect(BTree.getAt(tree, 100))->Expect.toBeNone
    t->expect(BTree.getAt(tree, 0))->Expect.toEqual(Some((1, "a")))
    t->expect(BTree.getAt(tree, 2))->Expect.toEqual(Some((3, "c")))
  })

  test("getAt returns entries in ascending key order, regardless of insertion order", t => {
    let tree =
      BTree.make(~id)
      ->BTree.set(5, "e")
      ->BTree.set(1, "a")
      ->BTree.set(3, "c")
      ->BTree.set(4, "d")
      ->BTree.set(2, "b")
    t->expect(BTree.getAt(tree, 0))->Expect.toEqual(Some((1, "a")))
    t->expect(BTree.getAt(tree, 1))->Expect.toEqual(Some((2, "b")))
    t->expect(BTree.getAt(tree, 2))->Expect.toEqual(Some((3, "c")))
    t->expect(BTree.getAt(tree, 3))->Expect.toEqual(Some((4, "d")))
    t->expect(BTree.getAt(tree, 4))->Expect.toEqual(Some((5, "e")))
  })

  test("indexOf returns the position of a present key, None for an absent one", t => {
    let tree = BTree.fromArray(~id, [(10, "a"), (20, "b"), (30, "c")])
    t->expect(BTree.indexOf(tree, 10))->Expect.toEqual(Some(0))
    t->expect(BTree.indexOf(tree, 20))->Expect.toEqual(Some(1))
    t->expect(BTree.indexOf(tree, 30))->Expect.toEqual(Some(2))
    t->expect(BTree.indexOf(tree, 15))->Expect.toBeNone
    t->expect(BTree.indexOf(tree, 5))->Expect.toBeNone
    t->expect(BTree.indexOf(tree, 999))->Expect.toBeNone
  })

  test("getAt and indexOf are inverses of each other at every position, across splits", t => {
    let tree = ref(BTree.make(~id, ~maxNodeSize=4))
    for key in 0 to 99 {
      tree := BTree.set(tree.contents, key, key * 10)
    }
    for index in 0 to 99 {
      let entry = BTree.getAt(tree.contents, index)
      t->expect(entry)->Expect.toEqual(Some((index, index * 10)))
      let (key, _) = Belt.Option.getWithDefault(entry, (-1, -1))
      t->expect(BTree.indexOf(tree.contents, key))->Expect.toEqual(Some(index))
    }
  })

  test("getAt and indexOf stay correct after removals shift entries around", t => {
    let tree = ref(BTree.make(~id, ~maxNodeSize=4))
    for key in 0 to 49 {
      tree := BTree.set(tree.contents, key, key)
    }
    // Remove every third key, leaving a sparse but still ascending sequence.
    let remaining = []
    for key in 0 to 49 {
      if mod(key, 3) == 0 {
        tree := BTree.remove(tree.contents, key)
      } else {
        Array.push(remaining, key)
      }
    }
    t->expect(BTree.size(tree.contents))->Expect.toBe(Array.length(remaining))
    Belt.Array.forEachWithIndex(
      remaining,
      (index, key) => {
        t->expect(BTree.getAt(tree.contents, index))->Expect.toEqual(Some((key, key)))
        t->expect(BTree.indexOf(tree.contents, key))->Expect.toEqual(Some(index))
      },
    )
  })
})

describe("BTree: splitting (small maxNodeSize forces it quickly)", () => {
  test(
    "inserting more than maxNodeSize entries still finds them all, in order, with valid structure throughout",
    t => {
      let tree = ref(BTree.make(~id, ~maxNodeSize=4))
      for key in 0 to 99 {
        tree := BTree.set(tree.contents, key, key * 10)
        BTree.checkInvariants(tree.contents)
      }
      t->expect(BTree.size(tree.contents))->Expect.toBe(100)
      for key in 0 to 99 {
        t->expect(BTree.get(tree.contents, key))->Expect.toEqual(Some(key * 10))
      }
      t->expect(BTree.keysArray(tree.contents))->Expect.toEqual(Belt.Array.makeBy(100, i => i))
    },
  )

  test("splitting works at the smallest allowed maxNodeSize (4)", t => {
    let tree = ref(BTree.make(~id, ~maxNodeSize=4))
    for key in 0 to 49 {
      tree := BTree.set(tree.contents, key, key)
      BTree.checkInvariants(tree.contents)
    }
    t->expect(BTree.size(tree.contents))->Expect.toBe(50)
  })
})

describe("BTree: removal, borrowing, and merging", () => {
  test(
    "removing forces borrowing and merging across many keys, and every survivor is still findable",
    t => {
      let tree = ref(BTree.make(~id, ~maxNodeSize=4))
      for key in 0 to 199 {
        tree := BTree.set(tree.contents, key, key)
      }
      // Remove every third key -- enough churn to force both borrowing (a
      // sibling has spare capacity) and merging (neither does) at multiple
      // levels, including cascading merges that shrink the root.
      let removedCount = ref(0)
      for key in 0 to 199 {
        if mod(key, 3) == 0 {
          tree := BTree.remove(tree.contents, key)
          BTree.checkInvariants(tree.contents)
          removedCount := removedCount.contents + 1
        }
      }
      t->expect(BTree.size(tree.contents))->Expect.toBe(200 - removedCount.contents)
      for key in 0 to 199 {
        let expected = mod(key, 3) == 0 ? None : Some(key)
        t->expect(BTree.get(tree.contents, key))->Expect.toEqual(expected)
      }
    },
  )

  test(
    "removing every key, one at a time, in ascending order, ends with an empty and valid tree",
    t => {
      let tree = ref(BTree.make(~id, ~maxNodeSize=4))
      for key in 0 to 99 {
        tree := BTree.set(tree.contents, key, key)
      }
      for key in 0 to 99 {
        tree := BTree.remove(tree.contents, key)
        BTree.checkInvariants(tree.contents)
      }
      t->expect(BTree.isEmpty(tree.contents))->Expect.toBeTruthy
    },
  )

  test(
    "removing every key, one at a time, in descending order, ends with an empty and valid tree",
    t => {
      let tree = ref(BTree.make(~id, ~maxNodeSize=4))
      for key in 0 to 99 {
        tree := BTree.set(tree.contents, key, key)
      }
      for key in 99 downto 0 {
        tree := BTree.remove(tree.contents, key)
        BTree.checkInvariants(tree.contents)
      }
      t->expect(BTree.isEmpty(tree.contents))->Expect.toBeTruthy
    },
  )

  test(
    "removing every key from the middle outward exercises both left- and right-side borrowing/merging",
    t => {
      let tree = ref(BTree.make(~id, ~maxNodeSize=4))
      for key in 0 to 99 {
        tree := BTree.set(tree.contents, key, key)
      }
      for offset in 0 to 49 {
        tree := BTree.remove(tree.contents, 50 + offset)
        BTree.checkInvariants(tree.contents)
        if 49 - offset >= 0 {
          tree := BTree.remove(tree.contents, 49 - offset)
          BTree.checkInvariants(tree.contents)
        }
      }
      t->expect(BTree.isEmpty(tree.contents))->Expect.toBeTruthy
    },
  )
})

/**
Cross-checks `tree`'s order-statistic operations against `oracleArray` --
a plain sorted array, assumed to already equal `BTree.toArray(tree)` (the
oracle stress tests below establish that separately): every position must
`getAt` back to the same entry, every present key must `indexOf` back to
its own position, and a couple of indices just outside the valid range
must still report `None`.
*/
let // Each check compares a whole array in one `expect`: the stress tests below
// call this after every step, and an `expect` per entry made them slow enough
// to time out on CI.
checkOrderStatistics = (t, tree, oracleArray: array<(int, int)>) => {
  t
  ->expect(oracleArray->Array.mapWithIndex((_, index) => BTree.getAt(tree, index)))
  ->Expect.toEqual(oracleArray->Array.map(entry => Some(entry)))
  t
  ->expect(oracleArray->Array.map(((key, _)) => BTree.indexOf(tree, key)))
  ->Expect.toEqual(oracleArray->Array.mapWithIndex((_, index) => Some(index)))
  t->expect(BTree.getAt(tree, -1))->Expect.toBeNone
  t->expect(BTree.getAt(tree, Array.length(oracleArray)))->Expect.toBeNone
}

describe("BTree: oracle stress tests (cross-checked against Belt.Map.Int)", () => {
  test("random insert/remove order matches a plain sorted map at every checkpoint", t => {
    let random = TestSupport.Random.make(20240521.0)
    let entryCount = 400
    let insertOrder = TestSupport.Random.shuffledRange(random, entryCount)
    let removeOrder = TestSupport.Random.shuffledRange(random, entryCount)

    let tree = ref(BTree.make(~id, ~maxNodeSize=4))
    let oracle = ref(Belt.Map.Int.empty)

    Belt.Array.forEach(
      insertOrder,
      key => {
        tree := BTree.set(tree.contents, key, key * 10)
        oracle := Belt.Map.Int.set(oracle.contents, key, key * 10)
        BTree.checkInvariants(tree.contents)
      },
    )
    t->expect(BTree.size(tree.contents))->Expect.toBe(Belt.Map.Int.size(oracle.contents))
    t->expect(BTree.toArray(tree.contents))->Expect.toEqual(Belt.Map.Int.toArray(oracle.contents))
    checkOrderStatistics(t, tree.contents, Belt.Map.Int.toArray(oracle.contents))

    // Remove two-thirds of the keys, in a different shuffled order.
    let removeCount = entryCount * 2 / 3
    Belt.Array.forEach(
      removeOrder->Belt.Array.slice(~offset=0, ~len=removeCount),
      key => {
        tree := BTree.remove(tree.contents, key)
        oracle := Belt.Map.Int.remove(oracle.contents, key)
        BTree.checkInvariants(tree.contents)
      },
    )
    t->expect(BTree.size(tree.contents))->Expect.toBe(Belt.Map.Int.size(oracle.contents))
    t->expect(BTree.toArray(tree.contents))->Expect.toEqual(Belt.Map.Int.toArray(oracle.contents))
    checkOrderStatistics(t, tree.contents, Belt.Map.Int.toArray(oracle.contents))

    // Remove the rest; both should end up empty together.
    Belt.Array.forEach(
      removeOrder->Belt.Array.slice(~offset=removeCount, ~len=entryCount - removeCount),
      key => {
        tree := BTree.remove(tree.contents, key)
        oracle := Belt.Map.Int.remove(oracle.contents, key)
        BTree.checkInvariants(tree.contents)
      },
    )
    t->expect(BTree.isEmpty(tree.contents))->Expect.toBeTruthy
    t->expect(Belt.Map.Int.isEmpty(oracle.contents))->Expect.toBeTruthy
    t->expect(BTree.getAt(tree.contents, 0))->Expect.toBeNone
  })

  test(
    "a long interleaved sequence of random inserts, overwrites, and removals matches a plain sorted map at every step",
    t => {
      let random = TestSupport.Random.make(998877.0)
      let tree = ref(BTree.make(~id, ~maxNodeSize=4))
      let oracle = ref(Belt.Map.Int.empty)
      // Keep the key space small relative to the step count, so removals
      // of already-absent keys (a no-op both here and on the oracle) and
      // re-insertions of already-present keys (an overwrite) both happen
      // often, alongside genuinely new insertions and real removals.
      let keySpace = 60
      for step in 0 to 999 {
        let key = TestSupport.Random.nextInt(random, keySpace)
        if mod(step, 3) == 0 {
          tree := BTree.remove(tree.contents, key)
          oracle := Belt.Map.Int.remove(oracle.contents, key)
        } else {
          let value = step
          tree := BTree.set(tree.contents, key, value)
          oracle := Belt.Map.Int.set(oracle.contents, key, value)
        }
        BTree.checkInvariants(tree.contents)
        let oracleArray = Belt.Map.Int.toArray(oracle.contents)
        t->expect(BTree.size(tree.contents))->Expect.toBe(Belt.Map.Int.size(oracle.contents))
        t->expect(BTree.toArray(tree.contents))->Expect.toEqual(oracleArray)
        checkOrderStatistics(t, tree.contents, oracleArray)
      }
    },
  )
})
