/***
See BTree_test.res's header comment for why this is `MutableBTree_test.res`.
*/

open Vitest

let id = TestSupport.intId

describe("MutableBTree: construction", () => {
  test(
    "make defaults to a maxNodeSize of 32, and accepts/clamps a custom one the same way BTree does",
    t => {
      t->expect(MutableBTree.maxNodeSize(MutableBTree.make(~id)))->Expect.toBe(32)
      t->expect(MutableBTree.maxNodeSize(MutableBTree.make(~id, ~maxNodeSize=8)))->Expect.toBe(8)
      t->expect(MutableBTree.maxNodeSize(MutableBTree.make(~id, ~maxNodeSize=1)))->Expect.toBe(32)
      t
      ->expect(MutableBTree.maxNodeSize(MutableBTree.make(~id, ~maxNodeSize=10000)))
      ->Expect.toBe(256)
    },
  )

  test(
    "fromArray seeds a mutable tree with the given entries; duplicate keys keep the later pair",
    t => {
      let tree = MutableBTree.fromArray(~id, [(2, "b"), (1, "a"), (3, "c"), (1, "a-again")])
      t->expect(MutableBTree.size(tree))->Expect.toBe(3)
      t->expect(MutableBTree.toArray(tree))->Expect.toEqual([(1, "a-again"), (2, "b"), (3, "c")])
    },
  )

  test("fromArray with an empty array is an empty tree", t => {
    t->expect(MutableBTree.isEmpty(MutableBTree.fromArray(~id, [])))->Expect.toBeTruthy
  })
})

describe("MutableBTree: empty and single-entry trees", () => {
  test("every read operation behaves as expected on an empty tree", t => {
    let tree = MutableBTree.make(~id)
    t->expect(MutableBTree.size(tree))->Expect.toBe(0)
    t->expect(MutableBTree.isEmpty(tree))->Expect.toBeTruthy
    t->expect(MutableBTree.get(tree, 1))->Expect.toBeNone
    t->expect(MutableBTree.has(tree, 1))->Expect.toBeFalsy
    t->expect(MutableBTree.minKey(tree))->Expect.toBeNone
    t->expect(MutableBTree.maxKey(tree))->Expect.toBeNone
    t->expect(MutableBTree.toArray(tree))->Expect.toEqual([])

    // Removing from an empty tree is a no-op, not an error.
    MutableBTree.remove(tree, 1)
    t->expect(MutableBTree.isEmpty(tree))->Expect.toBeTruthy
  })

  test("a single set/remove round-trip leaves the tree empty again", t => {
    let tree = MutableBTree.make(~id)
    MutableBTree.set(tree, 1, "one")
    t->expect(MutableBTree.size(tree))->Expect.toBe(1)
    t->expect(MutableBTree.get(tree, 1))->Expect.toEqual(Some("one"))
    MutableBTree.remove(tree, 1)
    t->expect(MutableBTree.isEmpty(tree))->Expect.toBeTruthy
  })
})

describe("MutableBTree: basic mutation", () => {
  test("set/get/has/size/remove behave like a mutable Map", t => {
    let tree = MutableBTree.make(~id)
    t->expect(MutableBTree.isEmpty(tree))->Expect.toBeTruthy

    MutableBTree.set(tree, 1, "one")
    MutableBTree.set(tree, 2, "two")
    t->expect(MutableBTree.size(tree))->Expect.toBe(2)
    t->expect(MutableBTree.get(tree, 1))->Expect.toEqual(Some("one"))
    t->expect(MutableBTree.has(tree, 2))->Expect.toBeTruthy

    MutableBTree.set(tree, 1, "uno") // overwrite, size unchanged
    t->expect(MutableBTree.size(tree))->Expect.toBe(2)
    t->expect(MutableBTree.get(tree, 1))->Expect.toEqual(Some("uno"))

    MutableBTree.remove(tree, 2)
    t->expect(MutableBTree.size(tree))->Expect.toBe(1)
    t->expect(MutableBTree.has(tree, 2))->Expect.toBeFalsy

    MutableBTree.remove(tree, 1)
    t->expect(MutableBTree.isEmpty(tree))->Expect.toBeTruthy
  })

  test("removing a missing key, or the same key twice, is a no-op", t => {
    let tree = MutableBTree.make(~id)
    MutableBTree.set(tree, 1, "one")
    MutableBTree.remove(tree, 999)
    t->expect(MutableBTree.size(tree))->Expect.toBe(1)
    MutableBTree.remove(tree, 1)
    MutableBTree.remove(tree, 1)
    t->expect(MutableBTree.isEmpty(tree))->Expect.toBeTruthy
  })

  test(
    "toArray/keysArray/valuesArray/forEach/reduce reflect the current contents, in key order",
    t => {
      let tree = MutableBTree.make(~id)
      MutableBTree.set(tree, 3, 30)
      MutableBTree.set(tree, 1, 10)
      MutableBTree.set(tree, 2, 20)

      t->expect(MutableBTree.toArray(tree))->Expect.toEqual([(1, 10), (2, 20), (3, 30)])
      t->expect(MutableBTree.keysArray(tree))->Expect.toEqual([1, 2, 3])
      t->expect(MutableBTree.valuesArray(tree))->Expect.toEqual([10, 20, 30])
      t->expect(MutableBTree.minKey(tree))->Expect.toEqual(Some(1))
      t->expect(MutableBTree.maxKey(tree))->Expect.toEqual(Some(3))

      let visited = []
      MutableBTree.forEach(tree, (key, value) => Array.push(visited, (key, value)))
      t->expect(visited)->Expect.toEqual([(1, 10), (2, 20), (3, 30)])

      let sum = MutableBTree.reduce(tree, 0, (accumulator, _key, value) => accumulator + value)
      t->expect(sum)->Expect.toBe(60)
    },
  )

  test("mutations are visible immediately -- there is no separate 'commit' step", t => {
    let tree = MutableBTree.make(~id)
    MutableBTree.set(tree, 1, "one")
    let sizeAfterFirstSet = MutableBTree.size(tree)
    MutableBTree.set(tree, 2, "two")
    t->expect(sizeAfterFirstSet)->Expect.toBe(1)
    t->expect(MutableBTree.size(tree))->Expect.toBe(2)
  })

  test(
    "mutating through one reference is visible through another reference to the exact same tree",
    t => {
      // The whole point of `MutableBTree` (as opposed to just using `BTree`
      // directly) is that `t` is a mutable cell: two bindings that refer to
      // the *same* `MutableBTree.t` value must observe each other's writes,
      // the same way two references to the same JS object would.
      let tree = MutableBTree.make(~id)
      let alias = tree
      MutableBTree.set(tree, 1, "one")
      t->expect(MutableBTree.get(alias, 1))->Expect.toEqual(Some("one"))

      MutableBTree.set(alias, 2, "two")
      t->expect(MutableBTree.get(tree, 2))->Expect.toEqual(Some("two"))
      t->expect(MutableBTree.size(tree))->Expect.toBe(2)

      MutableBTree.remove(alias, 1)
      t->expect(MutableBTree.has(tree, 1))->Expect.toBeFalsy
    },
  )
})

describe(
  "MutableBTree: splitting, borrowing, and merging (mirrors BTree_test.res, through the mutable API)",
  () => {
    test(
      "a long sequence of sets and removes keeps the tree valid and correct at every step",
      t => {
        let tree = MutableBTree.make(~id, ~maxNodeSize=4)
        for key in 0 to 149 {
          MutableBTree.set(tree, key, key * 10)
          MutableBTree.checkInvariants(tree)
        }
        t->expect(MutableBTree.size(tree))->Expect.toBe(150)

        for key in 0 to 149 {
          if mod(key, 2) == 0 {
            MutableBTree.remove(tree, key)
            MutableBTree.checkInvariants(tree)
          }
        }
        for key in 0 to 149 {
          let expected = mod(key, 2) == 0 ? None : Some(key * 10)
          t->expect(MutableBTree.get(tree, key))->Expect.toEqual(expected)
        }

        for key in 0 to 149 {
          MutableBTree.remove(tree, key)
        }
        MutableBTree.checkInvariants(tree)
        t->expect(MutableBTree.isEmpty(tree))->Expect.toBeTruthy
      },
    )
  },
)

describe("MutableBTree: order statistics (getAt / indexOf)", () => {
  test("getAt and indexOf on an empty tree always return None", t => {
    let tree = MutableBTree.make(~id)
    t->expect(MutableBTree.getAt(tree, 0))->Expect.toBeNone
    t->expect(MutableBTree.indexOf(tree, 1))->Expect.toBeNone
  })

  test("getAt/indexOf reflect in-place mutations immediately", t => {
    let tree = MutableBTree.make(~id)
    MutableBTree.set(tree, 2, "b")
    MutableBTree.set(tree, 1, "a")
    MutableBTree.set(tree, 3, "c")
    t->expect(MutableBTree.getAt(tree, 0))->Expect.toEqual(Some((1, "a")))
    t->expect(MutableBTree.getAt(tree, 1))->Expect.toEqual(Some((2, "b")))
    t->expect(MutableBTree.getAt(tree, 2))->Expect.toEqual(Some((3, "c")))
    t->expect(MutableBTree.getAt(tree, 3))->Expect.toBeNone
    t->expect(MutableBTree.indexOf(tree, 2))->Expect.toEqual(Some(1))

    MutableBTree.remove(tree, 2)
    t->expect(MutableBTree.getAt(tree, 1))->Expect.toEqual(Some((3, "c")))
    t->expect(MutableBTree.indexOf(tree, 2))->Expect.toBeNone
  })
})

describe("MutableBTree: snapshot", () => {
  test("a snapshot is unaffected by mutations made after it was taken", t => {
    let tree = MutableBTree.make(~id, ~maxNodeSize=4)
    for key in 0 to 49 {
      MutableBTree.set(tree, key, key)
    }
    let snapshotBefore = MutableBTree.snapshot(tree)

    MutableBTree.set(tree, 100, 1000)
    MutableBTree.remove(tree, 10)
    for key in 200 to 249 {
      MutableBTree.set(tree, key, key)
    }

    // The live tree reflects every mutation made after the snapshot...
    t->expect(MutableBTree.size(tree))->Expect.toBe(50 + 1 - 1 + 50)
    t->expect(MutableBTree.get(tree, 100))->Expect.toEqual(Some(1000))
    t->expect(MutableBTree.has(tree, 10))->Expect.toBeFalsy
    // ...but the snapshot taken before them still looks exactly like the
    // tree did at that moment.
    t->expect(BTree.size(snapshotBefore))->Expect.toBe(50)
    t->expect(BTree.get(snapshotBefore, 100))->Expect.toBeNone
    t->expect(BTree.get(snapshotBefore, 10))->Expect.toEqual(Some(10))
  })

  test(
    "two snapshots taken from the same mutable tree at different times are independent of each other",
    t => {
      let tree = MutableBTree.make(~id, ~maxNodeSize=4)
      MutableBTree.set(tree, 1, "one")
      let first = MutableBTree.snapshot(tree)
      MutableBTree.set(tree, 2, "two")
      let second = MutableBTree.snapshot(tree)
      MutableBTree.set(tree, 3, "three")

      t->expect(BTree.keysArray(first))->Expect.toEqual([1])
      t->expect(BTree.keysArray(second))->Expect.toEqual([1, 2])
      t->expect(MutableBTree.keysArray(tree))->Expect.toEqual([1, 2, 3])
    },
  )

  test(
    "diffing two snapshots of the same mutable tree reports exactly the mutations made in between",
    t => {
      let tree = MutableBTree.make(~id, ~maxNodeSize=4)
      for key in 0 to 199 {
        MutableBTree.set(tree, key, key)
      }
      let before = MutableBTree.snapshot(tree)

      MutableBTree.set(tree, 100, 999) // different
      MutableBTree.remove(tree, 150) // onlyLeft (present in `before`, not in `after`)
      MutableBTree.set(tree, 300, 3000) // onlyRight

      let after = MutableBTree.snapshot(tree)

      let onlyLeft = []
      let onlyRight = []
      let different = []
      BTree.diff(
        before,
        after,
        ~onlyLeft=(key, value) => Array.push(onlyLeft, (key, value)),
        ~onlyRight=(key, value) => Array.push(onlyRight, (key, value)),
        ~different=(key, leftValue, rightValue) =>
          Array.push(different, (key, leftValue, rightValue)),
      )
      t->expect(onlyLeft)->Expect.toEqual([(150, 150)])
      t->expect(onlyRight)->Expect.toEqual([(300, 3000)])
      t->expect(different)->Expect.toEqual([(100, 100, 999)])
      t->expect(BTree.sharedSubtreeCount(before, after))->Expect.Int.toBeGreaterThan(0)
    },
  )
})

describe("MutableBTree: oracle stress test (cross-checked against Belt.Map.Int)", () => {
  test(
    "a long interleaved sequence of random inserts, overwrites, and removals matches a plain sorted map at every step",
    t => {
      let random = TestSupport.Random.make(112233.0)
      let tree = MutableBTree.make(~id, ~maxNodeSize=4)
      let oracle = ref(Belt.Map.Int.empty)
      let keySpace = 60
      for step in 0 to 999 {
        let key = TestSupport.Random.nextInt(random, keySpace)
        if mod(step, 3) == 0 {
          MutableBTree.remove(tree, key)
          oracle := Belt.Map.Int.remove(oracle.contents, key)
        } else {
          MutableBTree.set(tree, key, step)
          oracle := Belt.Map.Int.set(oracle.contents, key, step)
        }
        MutableBTree.checkInvariants(tree)
        let oracleArray = Belt.Map.Int.toArray(oracle.contents)
        t->expect(MutableBTree.size(tree))->Expect.toBe(Belt.Map.Int.size(oracle.contents))
        t->expect(MutableBTree.toArray(tree))->Expect.toEqual(oracleArray)
        // One `expect` per array rather than per entry, which is slow enough
        // over every step to time out on CI.
        t
        ->expect(oracleArray->Array.mapWithIndex((_, index) => MutableBTree.getAt(tree, index)))
        ->Expect.toEqual(oracleArray->Array.map(entry => Some(entry)))
        t
        ->expect(oracleArray->Array.map(((key, _)) => MutableBTree.indexOf(tree, key)))
        ->Expect.toEqual(oracleArray->Array.mapWithIndex((_, index) => Some(index)))
      }
    },
  )
})
