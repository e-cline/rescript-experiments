/***
Tests `AvlTree.diff`: that it reports the right differences, and that it does so without
looking inside what the two trees share -- checked both with `sharedSubtreeCount` and by
counting how many entries a diff actually compares.
*/

open Vitest

let id = TestSupport.intId

type tree = AvlTree.t<int, int, TestSupport.IntCmp.identity>

type diffResult = {
  onlyLeft: array<(int, int)>,
  onlyRight: array<(int, int)>,
  different: array<(int, int, int)>,
}

let runDiff = (left: tree, right: tree): diffResult => {
  let result = {onlyLeft: [], onlyRight: [], different: []}
  AvlTree.diff(
    left,
    right,
    ~onlyLeft=(key, value) => Array.push(result.onlyLeft, (key, value)),
    ~onlyRight=(key, value) => Array.push(result.onlyRight, (key, value)),
    ~different=(key, leftValue, rightValue) =>
      Array.push(result.different, (key, leftValue, rightValue)),
  )
  result
}

/** What `runDiff` should produce, computed the slow, obvious way from each side's entries. */
let expectedDiff = (left: tree, right: tree): diffResult => {
  let result = {onlyLeft: [], onlyRight: [], different: []}
  AvlTree.forEach(left, (key, value) =>
    switch AvlTree.get(right, key) {
    | None => Array.push(result.onlyLeft, (key, value))
    | Some(rightValue) if rightValue != value =>
      Array.push(result.different, (key, value, rightValue))
    | Some(_) => ()
    }
  )
  AvlTree.forEach(right, (key, value) =>
    if !AvlTree.has(left, key) {
      Array.push(result.onlyRight, (key, value))
    }
  )
  result
}

/** How many pairs of entries `diff` compares the values of. */
let comparedEntryCount = (left: tree, right: tree): int => {
  let count = ref(0)
  AvlTree.diff(left, right, ~valueEqual=(a, b) => {
    count := count.contents + 1
    a == b
  })
  count.contents
}

let makeTree = (entries: array<(int, int)>): tree => AvlTree.fromArray(~id, entries)

let noDifferences = {onlyLeft: [], onlyRight: [], different: []}

describe("AvlTree.diff: correctness", () => {
  test("two empty trees have no differences", t => {
    t->expect(runDiff(AvlTree.make(~id), AvlTree.make(~id)))->Expect.toEqual(noDifferences)
  })

  test("an empty tree against a non-empty one reports every entry as onlyRight", t => {
    t
    ->expect(runDiff(AvlTree.make(~id), makeTree([(1, 10), (2, 20)])))
    ->Expect.toEqual({...noDifferences, onlyRight: [(1, 10), (2, 20)]})
  })

  test("a non-empty tree against an empty one reports every entry as onlyLeft", t => {
    t
    ->expect(runDiff(makeTree([(1, 10), (2, 20)]), AvlTree.make(~id)))
    ->Expect.toEqual({...noDifferences, onlyLeft: [(1, 10), (2, 20)]})
  })

  test("two trees with the same entries have no differences, regardless of insertion order", t => {
    t
    ->expect(runDiff(makeTree([(1, 10), (2, 20), (3, 30)]), makeTree([(3, 30), (1, 10), (2, 20)])))
    ->Expect.toEqual(noDifferences)
  })

  test("disjoint trees report every entry on the appropriate side", t => {
    t
    ->expect(runDiff(makeTree([(1, 10), (3, 30)]), makeTree([(2, 20), (4, 40)])))
    ->Expect.toEqual({
      ...noDifferences,
      onlyLeft: [(1, 10), (3, 30)],
      onlyRight: [(2, 20), (4, 40)],
    })
  })

  test("a longer tree's trailing entries are reported once the shorter one runs out", t => {
    let short = makeTree(Belt.Array.makeBy(10, key => (key, key)))
    let long = makeTree(Belt.Array.makeBy(100, key => (key, key)))
    let tail = Belt.Array.makeBy(90, index => (index + 10, index + 10))
    t->expect(runDiff(short, long))->Expect.toEqual({...noDifferences, onlyRight: tail})
    t->expect(runDiff(long, short))->Expect.toEqual({...noDifferences, onlyLeft: tail})
  })

  test("~valueEqual controls what counts as `different`", t => {
    let left = makeTree([(1, 10), (2, 20)])
    let right = makeTree([(1, 11), (2, 25)])
    let different = []
    AvlTree.diff(
      left,
      right,
      ~valueEqual=(a, b) => abs(a - b) <= 1,
      ~different=(key, _, _) => Array.push(different, key),
    )
    t->expect(different)->Expect.toEqual([2])
  })

  test("diff can be called with every callback omitted", t => {
    t
    ->expect(() => AvlTree.diff(makeTree([(1, 10)]), makeTree([(2, 20)])))
    ->Expect.not
    ->Expect.toThrow
  })

  test("trees with the same contents but entirely different shapes are diffed correctly", t => {
    let entries = Belt.Array.makeBy(500, key => (key, key))
    // Built balanced from sorted input on one side, by one-at-a-time insertion in descending
    // order on the other: same contents, no node in common.
    let balanced = makeTree(entries)
    let inserted = Belt.Array.reduceReverse(
      entries,
      AvlTree.make(~id),
      (tree, (key, value)) => AvlTree.set(tree, key, value),
    )
    t->expect(runDiff(balanced, inserted))->Expect.toEqual(noDifferences)
    t->expect(AvlTree.sharedSubtreeCount(balanced, inserted))->Expect.toBe(0)
  })
})

describe("AvlTree.diff: structural sharing", () => {
  let large = makeTree(Belt.Array.makeBy(10_000, key => (key * 2, key)))

  test("diffing a tree against itself skips the whole thing as one shared subtree", t => {
    t->expect(runDiff(large, large))->Expect.toEqual(noDifferences)
    t->expect(AvlTree.sharedSubtreeCount(large, large))->Expect.toBe(1)
    t->expect(comparedEntryCount(large, large))->Expect.toBe(0)
  })

  test("two empty trees share nothing (there is nothing to share)", t => {
    t->expect(AvlTree.sharedSubtreeCount(AvlTree.make(~id), AvlTree.make(~id)))->Expect.toBe(0)
  })

  test("an overwrite is found by comparing only the entries on the path to it", t => {
    let modified = AvlTree.set(large, 5000, -1)
    t
    ->expect(runDiff(large, modified))
    ->Expect.toEqual({...noDifferences, different: [(5000, 2500, -1)]})
    t->expect(AvlTree.sharedSubtreeCount(large, modified))->Expect.Int.toBeGreaterThan(0)
    // A 10,000-entry tree is about 14 levels deep.
    t->expect(comparedEntryCount(large, modified))->Expect.Int.toBeLessThan(30)
  })

  test("an insertion is found without comparing more than a few paths' worth of entries", t => {
    let modified = AvlTree.set(large, 5001, -1)
    t->expect(runDiff(large, modified))->Expect.toEqual({...noDifferences, onlyRight: [(5001, -1)]})
    t->expect(comparedEntryCount(large, modified))->Expect.Int.toBeLessThan(60)
    t->expect(comparedEntryCount(modified, large))->Expect.Int.toBeLessThan(60)
  })

  test("a removal is found without comparing more than a few paths' worth of entries", t => {
    let modified = AvlTree.remove(large, 5000)
    t
    ->expect(runDiff(large, modified))
    ->Expect.toEqual({...noDifferences, onlyLeft: [(5000, 2500)]})
    t->expect(comparedEntryCount(large, modified))->Expect.Int.toBeLessThan(60)
    t->expect(comparedEntryCount(modified, large))->Expect.Int.toBeLessThan(60)
  })

  test("sharedSubtreeCount is symmetric", t => {
    let modified = AvlTree.set(large, 5001, -1)
    t
    ->expect(AvlTree.sharedSubtreeCount(large, modified))
    ->Expect.toBe(AvlTree.sharedSubtreeCount(modified, large))
  })

  test(
    "after many random edits, including ones that rotate, diff still matches a plain comparison and still skips most of the tree",
    t => {
      let random = TestSupport.Random.make(424242.0)
      // Every edit below either inserts or removes, so each one changes sizes all the way up
      // its path and regularly triggers rotations: the shared subtrees end up at different
      // depths on the two sides, which is the case the size-guided walk exists for.
      for _ in 1 to 40 {
        let modified = ref(large)
        for _ in 1 to 25 {
          let key = TestSupport.Random.nextInt(random, 20_000)
          let current = modified.contents
          modified := (
              AvlTree.has(current, key)
                ? AvlTree.remove(current, key)
                : AvlTree.set(current, key, -key)
            )
        }
        t
        ->expect(runDiff(large, modified.contents))
        ->Expect.toEqual(expectedDiff(large, modified.contents))
        t
        ->expect(runDiff(modified.contents, large))
        ->Expect.toEqual(expectedDiff(modified.contents, large))
        // 25 edits to a tree about 14 levels deep: a few hundred entries near the edited
        // paths, not the 10,000 a walk that had lost its place would compare (about 225 at most, measured).
        t->expect(comparedEntryCount(large, modified.contents))->Expect.Int.toBeLessThan(500)
      }
    },
  )

  test("two trees edited independently from a common ancestor are diffed correctly", t => {
    let random = TestSupport.Random.make(77.0)
    let edit = (tree: tree): tree => {
      let current = ref(tree)
      for step in 1 to 200 {
        let key = TestSupport.Random.nextInt(random, 20_000)
        current := (
            mod(step, 3) == 0
              ? AvlTree.remove(current.contents, key)
              : AvlTree.set(current.contents, key, step)
          )
      }
      current.contents
    }
    let left = edit(large)
    let right = edit(large)
    AvlTree.checkInvariants(left)
    AvlTree.checkInvariants(right)
    t->expect(runDiff(left, right))->Expect.toEqual(expectedDiff(left, right))
    t->expect(AvlTree.sharedSubtreeCount(left, right))->Expect.Int.toBeGreaterThan(0)
  })

  test("differences of every kind are reported in one ascending pass over the keys", t => {
    // Edits spread across a large tree, so the diff moves between its in-step recursion and its
    // cursor walk many times: the callbacks must still come in key order across those switches.
    let random = TestSupport.Random.make(31337.0)
    let modified = ref(large)
    for step in 1 to 300 {
      let key = TestSupport.Random.nextInt(random, 20_000)
      modified := (
          mod(step, 2) == 0
            ? AvlTree.remove(modified.contents, key)
            : AvlTree.set(modified.contents, key, -step)
        )
    }
    let reportedKeys = []
    AvlTree.diff(
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

  test("trees built in different orders, so shaped differently at most levels", t => {
    // Whatever keys happen to line up between the two shapes are compared in step, and
    // everything else with cursors.
    let entries = Belt.Array.makeBy(1_001, key => (key, key))
    let balanced = makeTree(entries)
    let rootKey = switch AvlTree.getAt(balanced, 500) {
    | Some((key, _)) => key
    | None => -1
    }
    // The middle key first, then the rest in ascending order, rather than balanced from sorted input.
    let lopsided = ref(AvlTree.set(AvlTree.make(~id), rootKey, rootKey))
    for key in 0 to 1_000 {
      if key != 250 {
        lopsided := AvlTree.set(lopsided.contents, key, key == 750 ? -1 : key)
      }
    }
    AvlTree.checkInvariants(lopsided.contents)
    t
    ->expect(runDiff(balanced, lopsided.contents))
    ->Expect.toEqual({onlyLeft: [(250, 250)], onlyRight: [], different: [(750, 750, -1)]})
  })
})
