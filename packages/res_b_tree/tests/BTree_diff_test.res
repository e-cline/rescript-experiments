/***
Tests `BTree.diff` -- both its correctness (does it report the right
set of differences) and, via `BTree.sharedSubtreeCount`, the
structural-sharing property that makes it efficient (does it actually
recognize an untouched subtree as shared, rather than merely happening
to compare equal). See `BTree_test.res`'s header comment for why this
is `BTree_diff_test.res`, not `b_tree.diff.test.res`.
*/

open Vitest

let id = TestSupport.intId

/**
Collects a diff's callbacks into three plain arrays, for easy
`toEqual` assertions instead of hand-rolled counters in every test.
*/
type diffResult = {
  onlyLeft: array<(int, int)>,
  onlyRight: array<(int, int)>,
  different: array<(int, int, int)>,
}

let runDiff = (
  left: BTree.t<int, int, TestSupport.IntCmp.identity>,
  right: BTree.t<int, int, TestSupport.IntCmp.identity>,
): diffResult => {
  let result = {onlyLeft: [], onlyRight: [], different: []}
  BTree.diff(
    left,
    right,
    ~onlyLeft=(key, value) => Array.push(result.onlyLeft, (key, value)),
    ~onlyRight=(key, value) => Array.push(result.onlyRight, (key, value)),
    ~different=(key, leftValue, rightValue) =>
      Array.push(result.different, (key, leftValue, rightValue)),
  )
  result
}

let makeTree = (entries: array<(int, int)>): BTree.t<int, int, TestSupport.IntCmp.identity> =>
  BTree.fromArray(~id, ~maxNodeSize=4, entries)

describe("BTree.diff: correctness", () => {
  test("two empty trees have no differences", t => {
    let result = runDiff(BTree.make(~id), BTree.make(~id))
    t->expect(result.onlyLeft)->Expect.toEqual([])
    t->expect(result.onlyRight)->Expect.toEqual([])
    t->expect(result.different)->Expect.toEqual([])
  })

  test("an empty tree against a non-empty one reports every entry as onlyRight", t => {
    let result = runDiff(BTree.make(~id), makeTree([(1, 10), (2, 20)]))
    t->expect(result.onlyLeft)->Expect.toEqual([])
    t->expect(result.onlyRight)->Expect.toEqual([(1, 10), (2, 20)])
    t->expect(result.different)->Expect.toEqual([])
  })

  test("a non-empty tree against an empty one reports every entry as onlyLeft", t => {
    let result = runDiff(makeTree([(1, 10), (2, 20)]), BTree.make(~id))
    t->expect(result.onlyLeft)->Expect.toEqual([(1, 10), (2, 20)])
    t->expect(result.onlyRight)->Expect.toEqual([])
    t->expect(result.different)->Expect.toEqual([])
  })

  test("two trees with the same entries have no differences, regardless of insertion order", t => {
    let result = runDiff(
      makeTree([(1, 10), (2, 20), (3, 30)]),
      makeTree([(3, 30), (1, 10), (2, 20)]),
    )
    t->expect(result.onlyLeft)->Expect.toEqual([])
    t->expect(result.onlyRight)->Expect.toEqual([])
    t->expect(result.different)->Expect.toEqual([])
  })

  test("disjoint trees report every entry on the appropriate side", t => {
    let result = runDiff(makeTree([(1, 10), (3, 30)]), makeTree([(2, 20), (4, 40)]))
    t->expect(result.onlyLeft)->Expect.toEqual([(1, 10), (3, 30)])
    t->expect(result.onlyRight)->Expect.toEqual([(2, 20), (4, 40)])
    t->expect(result.different)->Expect.toEqual([])
  })

  test(
    "a shared key with different values is reported by `different`, in (key, leftValue, rightValue) order",
    t => {
      let result = runDiff(makeTree([(1, 10), (2, 20)]), makeTree([(1, 10), (2, 999)]))
      t->expect(result.onlyLeft)->Expect.toEqual([])
      t->expect(result.onlyRight)->Expect.toEqual([])
      t->expect(result.different)->Expect.toEqual([(2, 20, 999)])
    },
  )

  test("a mix of additions, removals, and changes across a larger tree", t => {
    // Built with a small `maxNodeSize` so this necessarily spans several
    // leaves and at least one level of internal nodes.
    let base = ref(BTree.make(~id, ~maxNodeSize=4))
    for key in 0 to 49 {
      base := BTree.set(base.contents, key, key)
    }
    let modified =
      base.contents
      ->BTree.remove(10) // onlyLeft
      ->BTree.remove(20) // onlyLeft
      ->BTree.set(30, 999) // different
      ->BTree.set(100, 1000) // onlyRight
      ->BTree.set(101, 1001) // onlyRight

    let result = runDiff(base.contents, modified)
    t->expect(result.onlyLeft)->Expect.toEqual([(10, 10), (20, 20)])
    t->expect(result.onlyRight)->Expect.toEqual([(100, 1000), (101, 1001)])
    t->expect(result.different)->Expect.toEqual([(30, 30, 999)])
  })

  test("~valueEqual controls what counts as `different`", t => {
    let left = makeTree([(1, 10), (2, 20)])
    let right = makeTree([(1, 11), (2, 21)])
    let differentCount = ref(0)
    // Every value differs by exactly 1 -- an equality function that
    // ignores that difference should report no changes at all.
    BTree.diff(
      left,
      right,
      ~valueEqual=(leftValue, rightValue) => abs(leftValue - rightValue) <= 1,
      ~different=(_, _, _) => differentCount := differentCount.contents + 1,
    )
    t->expect(differentCount.contents)->Expect.toBe(0)
  })

  test("the default ~valueEqual is exact (not just close)", t => {
    let left = makeTree([(1, 10)])
    let right = makeTree([(1, 11)])
    let result = runDiff(left, right)
    t->expect(result.different)->Expect.toEqual([(1, 10, 11)])
  })

  test("diff can be called with every callback omitted -- it just does nothing observable", t => {
    let left = makeTree([(1, 10), (2, 20)])
    let right = makeTree([(2, 999), (3, 30)])
    // Nothing to assert on directly; this is a smoke test that the
    // defaults for `onlyLeft`/`onlyRight`/`different`/`valueEqual` are
    // all valid on their own (no missing-argument crash) when a caller
    // only wants some of them -- or, as here, none at all.
    BTree.diff(left, right)
    t->expect(true)->Expect.toBeTruthy
  })

  test(
    "diff works correctly across two trees built with different maxNodeSize (and so, no shared structure at all)",
    t => {
      let entries = Belt.Array.makeBy(50, i => (i, i * 10))
      let smallNodes = BTree.fromArray(~id, ~maxNodeSize=4, entries)
      let bigNodes = BTree.fromArray(~id, ~maxNodeSize=64, entries)
      // Same content, but built with different branching factors, so the
      // two trees necessarily have completely different (and entirely
      // unshared) internal shapes -- `diff` has no choice but to fall back
      // to comparing individual entries the whole way through, which is
      // exactly the case this test exists to cover.
      let result = runDiff(smallNodes, bigNodes)
      t->expect(result.onlyLeft)->Expect.toEqual([])
      t->expect(result.onlyRight)->Expect.toEqual([])
      t->expect(result.different)->Expect.toEqual([])
      t->expect(BTree.sharedSubtreeCount(smallNodes, bigNodes))->Expect.toBe(0)
    },
  )
})

describe("BTree.diff: structural sharing", () => {
  // A tree big enough (with this small maxNodeSize) to have real
  // internal structure -- see the note on `sharedSubtreeCount` below for
  // why that matters for these tests specifically.
  let buildLargeTree = (): BTree.t<int, int, TestSupport.IntCmp.identity> => {
    let tree = ref(BTree.make(~id, ~maxNodeSize=4))
    for key in 0 to 199 {
      tree := BTree.set(tree.contents, key, key)
    }
    tree.contents
  }

  test("diffing a tree against itself shares every top-level subtree", t => {
    let tree = buildLargeTree()
    // Passing the exact same tree on both sides means the root cursors
    // start out already pointing at the same objects, so the very first
    // comparisons `diff` makes should skip everything.
    let result = runDiff(tree, tree)
    t->expect(result.onlyLeft)->Expect.toEqual([])
    t->expect(result.onlyRight)->Expect.toEqual([])
    t->expect(result.different)->Expect.toEqual([])
    t->expect(BTree.sharedSubtreeCount(tree, tree))->Expect.Int.toBeGreaterThan(0)
  })

  test(
    "changing one key in a large tree reports exactly that change, and shares most of the tree's structure",
    t => {
      let original = buildLargeTree()
      let modified = BTree.set(original, 100, 999)

      let result = runDiff(original, modified)
      t->expect(result.onlyLeft)->Expect.toEqual([])
      t->expect(result.onlyRight)->Expect.toEqual([])
      t->expect(result.different)->Expect.toEqual([(100, 100, 999)])

      // `diff` is still correct even if this weren't true -- it always
      // falls back to fully expanding whatever it can't prove is shared
      // (see the "correctness" tests above, all of which use trees with no
      // relation to each other at all) -- but for a 200-entry tree with
      // only a single key changed, most of the structure on both sides
      // should be the exact same objects, which is the entire reason
      // `diff` is cheap to run in the first place.
      t->expect(BTree.sharedSubtreeCount(original, modified))->Expect.Int.toBeGreaterThan(0)
    },
  )

  test(
    "removing one key from a large tree reports exactly that removal, and still shares structure",
    t => {
      let original = buildLargeTree()
      let modified = BTree.remove(original, 150)

      let result = runDiff(original, modified)
      t->expect(result.onlyLeft)->Expect.toEqual([(150, 150)])
      t->expect(result.onlyRight)->Expect.toEqual([])
      t->expect(result.different)->Expect.toEqual([])
      t->expect(BTree.sharedSubtreeCount(original, modified))->Expect.Int.toBeGreaterThan(0)
    },
  )

  test(
    "a tree small enough to be a single leaf is still skipped whole when diffed against itself",
    t => {
      // With the default maxNodeSize (32), a handful of entries is a single leaf, which is the
      // root. The diff skips any node that is the same object on both sides, a leaf as much as an
      // internal node, so this counts as one shared subtree and nothing is compared.
      let tree = makeTree([(1, 10), (2, 20), (3, 30)])
      t->expect(BTree.sharedSubtreeCount(tree, tree))->Expect.toBe(1)
      let result = runDiff(tree, tree)
      t->expect(result.onlyLeft)->Expect.toEqual([])
      t->expect(result.onlyRight)->Expect.toEqual([])
      t->expect(result.different)->Expect.toEqual([])
      // An edit to it gives a different leaf, which is compared entry by entry.
      let edited = BTree.set(tree, 2, 99)
      t->expect(BTree.sharedSubtreeCount(tree, edited))->Expect.toBe(0)
      t->expect(runDiff(tree, edited).different)->Expect.toEqual([(2, 20, 99)])
    },
  )

  test("two empty trees share nothing (there is nothing to share)", t => {
    t->expect(BTree.sharedSubtreeCount(BTree.make(~id), BTree.make(~id)))->Expect.toBe(0)
  })

  test(
    "after several edits, diff is still exactly correct against a plain oracle comparison",
    t => {
      let original = buildLargeTree()
      let modified = ref(original)
      let expectedOnlyLeft = []
      let expectedDifferent = []
      for key in 0 to 19 {
        if mod(key, 2) == 0 {
          modified := BTree.remove(modified.contents, key)
          Array.push(expectedOnlyLeft, (key, key))
        } else {
          modified := BTree.set(modified.contents, key, key + 10000)
          Array.push(expectedDifferent, (key, key, key + 10000))
        }
      }
      let result = runDiff(original, modified.contents)
      t->expect(result.onlyLeft)->Expect.toEqual(expectedOnlyLeft)
      t->expect(result.onlyRight)->Expect.toEqual([])
      t->expect(result.different)->Expect.toEqual(expectedDifferent)
    },
  )

  test("sharedSubtreeCount is symmetric -- it doesn't matter which tree is passed first", t => {
    let original = buildLargeTree()
    let modified = BTree.set(original, 100, 999)
    t
    ->expect(BTree.sharedSubtreeCount(original, modified))
    ->Expect.toBe(BTree.sharedSubtreeCount(modified, original))
  })
})
