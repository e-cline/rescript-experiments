/***
One test suite for any persistent sorted map with `AvlTree`'s interface, `SortedMap.S`, so that
an experimental tree structure can be checked against exactly what the existing ones are held to.
Not itself a test file: each candidate has a `*_test.res` next to this that applies `Make` to it.
*/

open Vitest

module type Config = {
  /** Shown in every test's name. */
  let name: string
  /**
  The most pairs of entries a diff may compare after 25 random insertions/removals in a
  10,000-entry tree: the measure of whether `diff` really skips what two trees share. `AvlTree`
  needs about 225; a structure with wide nodes legitimately needs more.
  */
  let maxComparedAfter25Edits: int
}

module Make = (Tree: SortedMap.S, Config: Config) => {
  let id = TestSupport.intId
  type tree = Tree.t<int, int, TestSupport.IntCmp.identity>

  type diffResult = {
    onlyLeft: array<(int, int)>,
    onlyRight: array<(int, int)>,
    different: array<(int, int, int)>,
  }
  let noDifferences = {onlyLeft: [], onlyRight: [], different: []}

  let runDiff = (left: tree, right: tree): diffResult => {
    let result = {onlyLeft: [], onlyRight: [], different: []}
    Tree.diff(
      left,
      right,
      ~onlyLeft=(key, value) => Array.push(result.onlyLeft, (key, value)),
      ~onlyRight=(key, value) => Array.push(result.onlyRight, (key, value)),
      ~different=(key, leftValue, rightValue) =>
        Array.push(result.different, (key, leftValue, rightValue)),
    )
    result
  }

  /** What `runDiff` should produce, computed the slow, obvious way. */
  let expectedDiff = (left: tree, right: tree): diffResult => {
    let result = {onlyLeft: [], onlyRight: [], different: []}
    Tree.forEach(left, (key, value) =>
      switch Tree.get(right, key) {
      | None => Array.push(result.onlyLeft, (key, value))
      | Some(rightValue) if rightValue != value =>
        Array.push(result.different, (key, value, rightValue))
      | Some(_) => ()
      }
    )
    Tree.forEach(right, (key, value) =>
      if !Tree.has(left, key) {
        Array.push(result.onlyRight, (key, value))
      }
    )
    result
  }

  let comparedEntryCount = (left: tree, right: tree): int => {
    let count = ref(0)
    Tree.diff(left, right, ~valueEqual=(a, b) => {
      count := count.contents + 1
      a == b
    })
    count.contents
  }

  let ascending = (count: int): array<(int, int)> =>
    Belt.Array.makeBy(count, key => (key, key * 10))

  /** Every read operation on `tree` against the oracle's sorted entries. */
  let checkAgainst = (t, tree: tree, oracleArray: array<(int, int)>) => {
    Tree.checkInvariants(tree)
    t->expect(Tree.size(tree))->Expect.toBe(Array.length(oracleArray))
    t->expect(Tree.isEmpty(tree))->Expect.toBe(Array.length(oracleArray) == 0)
    t->expect(Tree.toArray(tree))->Expect.toEqual(oracleArray)
    t->expect(Tree.keysArray(tree))->Expect.toEqual(oracleArray->Array.map(Pair.first))
    t->expect(Tree.valuesArray(tree))->Expect.toEqual(oracleArray->Array.map(Pair.second))
    t->expect(Tree.minKey(tree))->Expect.toEqual(oracleArray[0]->Option.map(Pair.first))
    t
    ->expect(Tree.maxKey(tree))
    ->Expect.toEqual(oracleArray[Array.length(oracleArray) - 1]->Option.map(Pair.first))
    let visited = []
    Tree.forEach(tree, (key, value) => Array.push(visited, (key, value)))
    t->expect(visited)->Expect.toEqual(oracleArray)
    t
    ->expect(Tree.reduce(tree, 0, (sum, key, value) => sum + key + value))
    ->Expect.toBe(oracleArray->Array.reduce(0, (sum, (key, value)) => sum + key + value))
    // The per-entry checks compare whole arrays, one `expect` each: the stress
    // tests call this after every step, and an `expect` per entry made them slow
    // enough to time out on CI.
    let keys = oracleArray->Array.map(Pair.first)
    t
    ->expect(keys->Array.map(key => Tree.get(tree, key)))
    ->Expect.toEqual(oracleArray->Array.map(((_, value)) => Some(value)))
    t->expect(keys->Array.every(key => Tree.has(tree, key)))->Expect.toBeTruthy
    t
    ->expect(oracleArray->Array.mapWithIndex((_, index) => Tree.getAt(tree, index)))
    ->Expect.toEqual(oracleArray->Array.map(entry => Some(entry)))
    t
    ->expect(keys->Array.map(key => Tree.indexOf(tree, key)))
    ->Expect.toEqual(oracleArray->Array.mapWithIndex((_, index) => Some(index)))
    t->expect(Tree.getAt(tree, -1))->Expect.toBeNone
    t->expect(Tree.getAt(tree, Array.length(oracleArray)))->Expect.toBeNone
  }

  describe(`${Config.name}: basics`, () => {
    test("an empty tree", t => {
      let tree: tree = Tree.make(~id)
      checkAgainst(t, tree, [])
      t->expect(Tree.get(tree, 1))->Expect.toBeNone
      t->expect(Tree.has(tree, 1))->Expect.toBeFalsy
      t->expect(Tree.indexOf(tree, 1))->Expect.toBeNone
      t->expect(Tree.remove(tree, 1) === tree)->Expect.toBeTruthy
      checkAgainst(t, Tree.fromArray(~id, []), [])
    })

    test("a single entry, then none again", t => {
      let tree = Tree.set(Tree.make(~id), 7, 70)
      checkAgainst(t, tree, [(7, 70)])
      checkAgainst(t, Tree.remove(tree, 7), [])
    })

    test("fromArray: unsorted input, sorted input at every small size, and duplicate keys", t => {
      checkAgainst(
        t,
        Tree.fromArray(~id, [(5, 50), (1, 10), (3, 30), (2, 20), (4, 40)]),
        [(1, 10), (2, 20), (3, 30), (4, 40), (5, 50)],
      )
      for count in 0 to 80 {
        checkAgainst(t, Tree.fromArray(~id, ascending(count)), ascending(count))
      }
      checkAgainst(
        t,
        Tree.fromArray(~id, [(2, 20), (1, 10), (3, 30), (1, 11)]),
        [(1, 11), (2, 20), (3, 30)],
      )
      checkAgainst(
        t,
        Tree.fromArray(~id, [(1, 10), (2, 20), (2, 21), (3, 30)]),
        [(1, 10), (2, 21), (3, 30)],
      )
    })

    test("set and remove leave the tree they were called on untouched", t => {
      let original = Tree.fromArray(~id, ascending(100))
      let _ = Tree.set(original, 1000, 1)
      let _ = Tree.set(original, 50, -1)
      let _ = Tree.remove(original, 50)
      checkAgainst(t, original, ascending(100))
    })

    test("removing a missing key returns the exact same tree", t => {
      let tree = Tree.fromArray(~id, ascending(100))
      t->expect(Tree.remove(tree, -5) === tree)->Expect.toBeTruthy
      t->expect(Tree.remove(tree, 1000) === tree)->Expect.toBeTruthy
    })

    test("a present key whose value is None is still present", t => {
      let tree = Tree.fromArray(~id, [(1, None), (2, Some("two"))])
      t->expect(Tree.has(tree, 1))->Expect.toBeTruthy
      t->expect(Tree.get(tree, 1))->Expect.toEqual(Some(None))
      t->expect(Tree.get(tree, 3))->Expect.toEqual(None)
    })
  })

  describe(`${Config.name}: structure under ordered edits`, () => {
    let orders = [
      ("ascending", Belt.Array.makeBy(600, index => index)),
      ("descending", Belt.Array.makeBy(600, index => 599 - index)),
      (
        "outside in",
        Belt.Array.makeBy(600, index => mod(index, 2) == 0 ? index / 2 : 599 - index / 2),
      ),
      (
        "inside out",
        Belt.Array.makeBy(600, index => mod(index, 2) == 0 ? 300 + index / 2 : 299 - index / 2),
      ),
    ]
    orders->Array.forEach(((orderName, order)) => {
      test(
        `inserting ${orderName}`,
        t => {
          let tree = ref(Tree.make(~id))
          order->Array.forEach(
            key => {
              tree := Tree.set(tree.contents, key, key * 10)
              Tree.checkInvariants(tree.contents)
            },
          )
          checkAgainst(t, tree.contents, ascending(600))
        },
      )
      test(
        `removing ${orderName}`,
        t => {
          let tree = ref(Tree.fromArray(~id, ascending(600)))
          order->Array.forEachWithIndex(
            (key, index) => {
              tree := Tree.remove(tree.contents, key)
              Tree.checkInvariants(tree.contents)
              t->expect(Tree.size(tree.contents))->Expect.toBe(599 - index)
              t->expect(Tree.has(tree.contents, key))->Expect.toBeFalsy
            },
          )
        },
      )
    })
  })

  describe(`${Config.name}: oracle stress tests (against Belt.Map.Int)`, () => {
    test("random inserts then random removals, checked in full at intervals", t => {
      let random = TestSupport.Random.make(20240521.0)
      let entryCount = 3_000
      let insertOrder = TestSupport.Random.shuffledRange(random, entryCount)
      let removeOrder = TestSupport.Random.shuffledRange(random, entryCount)
      let tree = ref(Tree.make(~id))
      let oracle = ref(Belt.Map.Int.empty)
      insertOrder->Array.forEachWithIndex(
        (key, step) => {
          tree := Tree.set(tree.contents, key, key * 10)
          oracle := Belt.Map.Int.set(oracle.contents, key, key * 10)
          Tree.checkInvariants(tree.contents)
          if mod(step, 500) == 499 {
            checkAgainst(t, tree.contents, Belt.Map.Int.toArray(oracle.contents))
          }
        },
      )
      removeOrder->Array.forEachWithIndex(
        (key, step) => {
          tree := Tree.remove(tree.contents, key)
          oracle := Belt.Map.Int.remove(oracle.contents, key)
          Tree.checkInvariants(tree.contents)
          if mod(step, 500) == 499 {
            checkAgainst(t, tree.contents, Belt.Map.Int.toArray(oracle.contents))
          }
        },
      )
      t->expect(Tree.isEmpty(tree.contents))->Expect.toBeTruthy
    })

    [60, 400]->Array.forEach(keySpace =>
      test(
        `interleaved inserts, overwrites and removals over ${Int.toString(keySpace)} keys`,
        t => {
          let random = TestSupport.Random.make(998877.0 +. Int.toFloat(keySpace))
          let tree = ref(Tree.make(~id))
          let oracle = ref(Belt.Map.Int.empty)
          for step in 0 to 1_999 {
            let key = TestSupport.Random.nextInt(random, keySpace)
            if mod(step, 3) == 0 {
              tree := Tree.remove(tree.contents, key)
              oracle := Belt.Map.Int.remove(oracle.contents, key)
            } else {
              tree := Tree.set(tree.contents, key, step)
              oracle := Belt.Map.Int.set(oracle.contents, key, step)
            }
            Tree.checkInvariants(tree.contents)
            if keySpace <= 60 || mod(step, 20) == 0 {
              checkAgainst(t, tree.contents, Belt.Map.Int.toArray(oracle.contents))
            }
          }
        },
      )
    )
  })

  describe(`${Config.name}: diff`, () => {
    let makeTree = (entries: array<(int, int)>): tree => Tree.fromArray(~id, entries)
    let large = makeTree(Belt.Array.makeBy(10_000, key => (key * 2, key)))
    let insertedOneByOne = (entries: array<(int, int)>): tree =>
      entries->Array.reduce(Tree.make(~id), (tree, (key, value)) => Tree.set(tree, key, value))

    test("empty and non-empty trees", t => {
      t->expect(runDiff(Tree.make(~id), Tree.make(~id)))->Expect.toEqual(noDifferences)
      t
      ->expect(runDiff(Tree.make(~id), makeTree([(1, 10), (2, 20)])))
      ->Expect.toEqual({...noDifferences, onlyRight: [(1, 10), (2, 20)]})
      t
      ->expect(runDiff(makeTree([(1, 10), (2, 20)]), Tree.make(~id)))
      ->Expect.toEqual({...noDifferences, onlyLeft: [(1, 10), (2, 20)]})
    })

    test("disjoint trees, and one tree a prefix of the other", t => {
      t
      ->expect(runDiff(makeTree([(1, 10), (3, 30)]), makeTree([(2, 20), (4, 40)])))
      ->Expect.toEqual({
        ...noDifferences,
        onlyLeft: [(1, 10), (3, 30)],
        onlyRight: [(2, 20), (4, 40)],
      })
      let short = makeTree(Belt.Array.makeBy(10, key => (key, key)))
      let long = makeTree(Belt.Array.makeBy(300, key => (key, key)))
      let tail = Belt.Array.makeBy(290, index => (index + 10, index + 10))
      t->expect(runDiff(short, long))->Expect.toEqual({...noDifferences, onlyRight: tail})
      t->expect(runDiff(long, short))->Expect.toEqual({...noDifferences, onlyLeft: tail})
    })

    test("~valueEqual decides what counts as different, and every callback is optional", t => {
      let different = []
      Tree.diff(
        makeTree([(1, 10), (2, 20)]),
        makeTree([(1, 11), (2, 25)]),
        ~valueEqual=(a, b) => abs(a - b) <= 1,
        ~different=(key, _, _) => Array.push(different, key),
      )
      t->expect(different)->Expect.toEqual([2])
      t
      ->expect(() => Tree.diff(makeTree([(1, 10)]), makeTree([(2, 20)])))
      ->Expect.not
      ->Expect.toThrow
    })

    test("equal contents built in different orders", t => {
      let entries = Belt.Array.makeBy(2_000, key => (key, key))
      let random = TestSupport.Random.make(5.0)
      let shuffled = TestSupport.Random.shuffledRange(random, 2_000)->Array.map(key => (key, key))
      let trees = [
        makeTree(entries),
        insertedOneByOne(entries),
        insertedOneByOne(entries->Array.toReversed),
        insertedOneByOne(shuffled),
      ]
      trees->Array.forEach(
        left =>
          trees->Array.forEach(
            right => t->expect(runDiff(left, right))->Expect.toEqual(noDifferences),
          ),
      )
    })

    test("a tree against itself compares nothing", t => {
      t->expect(runDiff(large, large))->Expect.toEqual(noDifferences)
      t->expect(comparedEntryCount(large, large))->Expect.toBe(0)
      t->expect(Tree.sharedSubtreeCount(large, large))->Expect.Int.toBeGreaterThan(0)
      t->expect(Tree.sharedSubtreeCount(Tree.make(~id), Tree.make(~id)))->Expect.toBe(0)
    })

    test("single edits to a large tree", t => {
      t
      ->expect(runDiff(large, Tree.set(large, 5000, -1)))
      ->Expect.toEqual({...noDifferences, different: [(5000, 2500, -1)]})
      t
      ->expect(runDiff(large, Tree.set(large, 5001, -1)))
      ->Expect.toEqual({...noDifferences, onlyRight: [(5001, -1)]})
      t
      ->expect(runDiff(large, Tree.remove(large, 5000)))
      ->Expect.toEqual({...noDifferences, onlyLeft: [(5000, 2500)]})
    })

    test(
      "random batches of insertions and removals match a plain comparison, and skip most of the tree",
      t => {
        let random = TestSupport.Random.make(424242.0)
        for _ in 1 to 40 {
          let modified = ref(large)
          for _ in 1 to 25 {
            let key = TestSupport.Random.nextInt(random, 20_000)
            let current = modified.contents
            modified := (
                Tree.has(current, key) ? Tree.remove(current, key) : Tree.set(current, key, -key)
              )
          }
          Tree.checkInvariants(modified.contents)
          t
          ->expect(runDiff(large, modified.contents))
          ->Expect.toEqual(expectedDiff(large, modified.contents))
          t
          ->expect(runDiff(modified.contents, large))
          ->Expect.toEqual(expectedDiff(modified.contents, large))
          t
          ->expect(comparedEntryCount(large, modified.contents))
          ->Expect.Int.toBeLessThan(Config.maxComparedAfter25Edits)
          t
          ->expect(comparedEntryCount(modified.contents, large))
          ->Expect.Int.toBeLessThan(Config.maxComparedAfter25Edits)
        }
      },
    )

    test("two trees edited independently from a common ancestor", t => {
      let random = TestSupport.Random.make(77.0)
      let edit = (tree: tree): tree => {
        let current = ref(tree)
        for step in 1 to 300 {
          let key = TestSupport.Random.nextInt(random, 20_000)
          current := (
              mod(step, 3) == 0
                ? Tree.remove(current.contents, key)
                : Tree.set(current.contents, key, step)
            )
        }
        current.contents
      }
      let left = edit(large)
      let right = edit(large)
      t->expect(runDiff(left, right))->Expect.toEqual(expectedDiff(left, right))
      t->expect(Tree.sharedSubtreeCount(left, right))->Expect.Int.toBeGreaterThan(0)
    })

    test("differences of every kind come in one ascending pass over the keys", t => {
      let random = TestSupport.Random.make(31337.0)
      let modified = ref(large)
      for step in 1 to 300 {
        let key = TestSupport.Random.nextInt(random, 20_000)
        modified := (
            mod(step, 2) == 0
              ? Tree.remove(modified.contents, key)
              : Tree.set(modified.contents, key, -step)
          )
      }
      let reportedKeys = []
      Tree.diff(
        large,
        modified.contents,
        ~onlyLeft=(key, _) => Array.push(reportedKeys, key),
        ~onlyRight=(key, _) => Array.push(reportedKeys, key),
        ~different=(key, _, _) => Array.push(reportedKeys, key),
      )
      t->expect(Array.length(reportedKeys))->Expect.Int.toBeGreaterThan(200)
      t
      ->expect(reportedKeys)
      ->Expect.toEqual(reportedKeys->Array.toSorted((a, b) => Int.toFloat(a - b)))
    })
  })
}
