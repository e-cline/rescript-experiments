/***
`BTree` at node sizes 8, 16 and 32: the shared conformance suite, then what that suite cannot see
from outside the tree (where nodes split, borrow and merge, which arrays an edit reuses, and how
much a diff looks at). `BTree_test.res` and `BTree_diff_test.res` cover the public API itself.
*/

open Vitest

/**
`maxComparedAfter25Edits` is 25 times the node size: a diff has to merge each leaf an edit changed
with the leaf it was before, which is at most a node's worth of pairs per edit, and it should look
at nothing else. The most seen across the suite's 40 batches (both directions) is 192, 392 and 790
at node sizes 8, 16 and 32. That is against a tree from `fromArray`, whose leaves are full; in a
tree built by insertion, as the benchmarks' are, it is 166, 318 and 610.
*/
/**
`BTree` at a fixed node size, with `AvlTree`'s `make`/`fromArray` (no `maxNodeSize` argument), as
`Conformance.Make` and `Focused` below need.
*/
module Sized = (
  Size: {
    let maxNodeSize: int
  },
) => {
  include BTree
  let make = (~id) => BTree.make(~id, ~maxNodeSize=Size.maxNodeSize)
  let fromArray = (~id, entries) => BTree.fromArray(~id, ~maxNodeSize=Size.maxNodeSize, entries)
  let maxNodeSize = Size.maxNodeSize
  let minNodeSize = (Size.maxNodeSize + 1) / 2
}

module BTree8 = Sized({
  let maxNodeSize = 8
})
module BTree16 = Sized({
  let maxNodeSize = 16
})
module BTree32 = Sized({
  let maxNodeSize = 32
})

module Conformance8 = Conformance.Make(
  BTree8,
  {
    let name = "BTree, nodes of 8"
    let maxComparedAfter25Edits = 200
  },
)

module Conformance16 = Conformance.Make(
  BTree16,
  {
    let name = "BTree, nodes of 16"
    let maxComparedAfter25Edits = 400
  },
)

module Conformance32 = Conformance.Make(
  BTree32,
  {
    let name = "BTree, nodes of 32"
    let maxComparedAfter25Edits = 800
  },
)

module Focused = (
  Tree: module type of BTree8,
  Config: {
    let name: string
  },
) => {
  let id = TestSupport.intId
  type tree = Tree.t<int, int, TestSupport.IntCmp.identity>
  type node = Node.t<int, int>

  let max = Tree.maxNodeSize
  let min = Tree.minNodeSize

  let ascending = (count: int): array<(int, int)> =>
    Belt.Array.makeBy(count, key => (key, key * 10))

  let rootOf = (tree: tree): node => Tree.root(tree)->Option.getOrThrow

  /** The width of every child of the root, left to right. */
  let childWidths = (tree: tree): array<int> => Node.children(rootOf(tree))->Array.map(Node.width)

  /** The nodes from the root down to the leaf that `key` belongs in. */
  let pathTo = (tree: tree, key: int): array<node> => {
    let path = []
    let node = ref(rootOf(tree))
    Array.push(path, node.contents)
    while !Node.isLeaf(node.contents) {
      let found = Node.search(node.contents.keys, key, (a, b) => a - b)
      node := Node.childAt(node.contents.links, Node.childIndex(found))
      Array.push(path, node.contents)
    }
    path
  }

  type diffResult = {
    onlyLeft: array<(int, int)>,
    onlyRight: array<(int, int)>,
    different: array<(int, int, int)>,
  }

  /** The differences between two trees, and how many pairs of values the diff compared. */
  let runDiff = (left: tree, right: tree): (diffResult, int) => {
    let result = {onlyLeft: [], onlyRight: [], different: []}
    let compared = ref(0)
    let reportedKeys = []
    Tree.diff(
      left,
      right,
      ~valueEqual=(a, b) => {
        compared := compared.contents + 1
        a == b
      },
      ~onlyLeft=(key, value) => {
        Array.push(reportedKeys, key)
        Array.push(result.onlyLeft, (key, value))
      },
      ~onlyRight=(key, value) => {
        Array.push(reportedKeys, key)
        Array.push(result.onlyRight, (key, value))
      },
      ~different=(key, leftValue, rightValue) => {
        Array.push(reportedKeys, key)
        Array.push(result.different, (key, leftValue, rightValue))
      },
    )
    if reportedKeys != reportedKeys->Array.toSorted((a, b) => Int.toFloat(a - b)) {
      JsError.throwWithMessage("diff callbacks out of key order")
    }
    (result, compared.contents)
  }

  /** What `runDiff` should find, computed the slow, obvious way. */
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

  let expectDiffBothWays = (t, left: tree, right: tree) => {
    let (forwards, _) = runDiff(left, right)
    t->expect(forwards)->Expect.toEqual(expectedDiff(left, right))
    let (backwards, _) = runDiff(right, left)
    t->expect(backwards)->Expect.toEqual(expectedDiff(right, left))
  }

  describe(`${Config.name}: splitting`, () => {
    test("a root leaf fills to the maximum, and splits in two on the next insertion", t => {
      let full = Tree.fromArray(~id, ascending(max))
      t->expect(Node.isLeaf(rootOf(full)))->Expect.toBeTruthy
      t->expect(Node.width(rootOf(full)))->Expect.toBe(max)
      // At the end, at the start, and in the middle.
      [max * 10, -1, max / 2 * 10 + 5]->Array.forEach(
        key => {
          let tree = Tree.set(
            Tree.fromArray(~id, ascending(max)->Array.map(((k, v)) => (k * 10, v))),
            key,
            1,
          )
          Tree.checkInvariants(tree)
          t->expect(Node.isLeaf(rootOf(tree)))->Expect.toBeFalsy
          t->expect(childWidths(tree))->Expect.toEqual([(max + 1) / 2, max + 1 - (max + 1) / 2])
          t->expect(Node.counts(rootOf(tree)))->Expect.toEqual([(max + 1) / 2, max + 1])
          t->expect(Tree.size(tree))->Expect.toBe(max + 1)
          // The separator is the right leaf's first key.
          t
          ->expect(rootOf(tree).keys)
          ->Expect.toEqual([Array.getUnsafe(Node.childAt(rootOf(tree).links, 1).keys, 0)])
        },
      )
    })

    test(
      "an internal root fills to the maximum, and the tree grows a level on the next split",
      t => {
        // Ascending insertion leaves every leaf but the last at the minimum, so the root gains a
        // child every `max + 1 - min` insertions or so.
        let tree = ref(Tree.make(~id))
        let key = ref(0)
        while (
          Tree.isEmpty(tree.contents) ||
          Node.isLeaf(rootOf(tree.contents)) ||
          Node.width(rootOf(tree.contents)) < max
        ) {
          tree := Tree.set(tree.contents, key.contents, key.contents)
          key := key.contents + 1
        }
        t->expect(Node.height(rootOf(tree.contents), 0))->Expect.toBe(1)
        while Node.height(rootOf(tree.contents), 0) == 1 {
          t->expect(Node.width(rootOf(tree.contents)))->Expect.toBe(max)
          tree := Tree.set(tree.contents, key.contents, key.contents)
          key := key.contents + 1
          Tree.checkInvariants(tree.contents)
        }
        t->expect(Node.height(rootOf(tree.contents), 0))->Expect.toBe(2)
        t
        ->expect(childWidths(tree.contents))
        ->Expect.toEqual([(max + 1) / 2, max + 1 - (max + 1) / 2])
        t
        ->expect(Tree.toArray(tree.contents))
        ->Expect.toEqual(Belt.Array.makeBy(key.contents, key => (key, key)))
      },
    )
  })

  describe(`${Config.name}: borrowing and merging`, () => {
    // Two leaves under the root: the left with one key more than the minimum when `max` is even,
    // and both at the minimum when it is odd. Keys are 0, 10, 20, ...
    let twoLeaves = (): tree =>
      Tree.fromArray(~id, Belt.Array.makeBy(max + 1, index => (index * 10, index)))

    test("a leaf below the minimum borrows from a left sibling that has one to spare", t => {
      let tree = twoLeaves()
      let leftWidth = max + 1 - min
      t->expect(childWidths(tree))->Expect.toEqual([leftWidth, min])
      // Give the left leaf a spare key whatever `max` is.
      let tree = Tree.set(tree, 5, -1)
      let removed = Tree.remove(tree, max * 10)
      Tree.checkInvariants(removed)
      t->expect(childWidths(removed))->Expect.toEqual([leftWidth, min])
      t->expect(Node.counts(rootOf(removed)))->Expect.toEqual([leftWidth, leftWidth + min])
      // The key that moved over is the new boundary.
      t->expect(rootOf(removed).keys)->Expect.toEqual([(leftWidth - 1) * 10])
      t->expect(Tree.get(removed, (leftWidth - 1) * 10))->Expect.toEqual(Some(leftWidth - 1))
      t->expect(Tree.indexOf(removed, (leftWidth - 1) * 10))->Expect.toEqual(Some(leftWidth))
    })

    test("a leaf below the minimum borrows from a right sibling that has one to spare", t => {
      // Bring the left leaf down to the minimum, and the right one above it.
      let tree = ref(Tree.set(twoLeaves(), max * 10 + 1, -1))
      let leftWidth = ref(max + 1 - min)
      let nextKey = ref(0)
      while leftWidth.contents > min {
        tree := Tree.remove(tree.contents, nextKey.contents)
        nextKey := nextKey.contents + 10
        leftWidth := leftWidth.contents - 1
      }
      t->expect(childWidths(tree.contents))->Expect.toEqual([min, min + 1])
      let oldBoundary = Array.getUnsafe(rootOf(tree.contents).keys, 0)
      let removed = Tree.remove(tree.contents, nextKey.contents)
      Tree.checkInvariants(removed)
      t->expect(childWidths(removed))->Expect.toEqual([min, min])
      t->expect(Node.counts(rootOf(removed)))->Expect.toEqual([min, 2 * min])
      // The old boundary key moved left, and the next key up is the new boundary.
      t->expect(rootOf(removed).keys)->Expect.toEqual([oldBoundary + 10])
      t->expect(Tree.indexOf(removed, oldBoundary))->Expect.toEqual(Some(min - 1))
    })

    test("two leaves at the minimum merge, and a root left with one child gives way to it", t => {
      let tree = ref(twoLeaves())
      let nextKey = ref(0)
      // Bring the left leaf down to the minimum; the right is there already.
      for _ in 1 to max + 1 - 2 * min {
        tree := Tree.remove(tree.contents, nextKey.contents)
        nextKey := nextKey.contents + 10
      }
      t->expect(childWidths(tree.contents))->Expect.toEqual([min, min])
      // Removing from either side merges the two into a root leaf.
      [nextKey.contents, max * 10]->Array.forEach(
        key => {
          let merged = Tree.remove(tree.contents, key)
          Tree.checkInvariants(merged)
          t->expect(Node.isLeaf(rootOf(merged)))->Expect.toBeTruthy
          t->expect(Node.width(rootOf(merged)))->Expect.toBe(2 * min - 1)
          t->expect(Tree.has(merged, key))->Expect.toBeFalsy
        },
      )
    })

    test(
      "internal nodes borrow and merge as a tall tree is emptied from either end and the middle",
      t => {
        let count = max * max * 2
        let entries = ascending(count)
        let orders = [
          Belt.Array.makeBy(count, index => index),
          Belt.Array.makeBy(count, index => count - 1 - index),
          Belt.Array.makeBy(
            count,
            index => mod(index, 2) == 0 ? count / 2 + index / 2 : count / 2 - 1 - index / 2,
          ),
        ]
        orders->Array.forEach(
          order => {
            // Built by insertion, so that the nodes start near the minimum.
            let tree = ref(
              entries->Array.reduce(
                Tree.make(~id),
                (tree, (key, value)) => Tree.set(tree, key, value),
              ),
            )
            t->expect(Node.height(rootOf(tree.contents), 0))->Expect.Int.toBeGreaterThan(1)
            order->Array.forEachWithIndex(
              (key, step) => {
                tree := Tree.remove(tree.contents, key)
                Tree.checkInvariants(tree.contents)
                if mod(step, 97) == 0 {
                  t->expect(Tree.size(tree.contents))->Expect.toBe(count - 1 - step)
                  t
                  ->expect(Tree.getAt(tree.contents, 0))
                  ->Expect.toEqual(Tree.minKey(tree.contents)->Option.map(key => (key, key * 10)))
                }
              },
            )
            t->expect(Tree.isEmpty(tree.contents))->Expect.toBeTruthy
          },
        )
      },
    )
  })

  describe(`${Config.name}: what an edit reuses`, () => {
    let tall: tree = Tree.fromArray(~id, ascending(max * max * 3))
    let key = max * max + 3

    test(
      "an overwrite reuses every keys array, and copies only a leaf's values and the links above it",
      t => {
        let overwritten = Tree.set(tall, key, -1)
        let before = pathTo(tall, key)
        let after = pathTo(overwritten, key)
        t->expect(Array.length(before))->Expect.toBe(3)
        t->expect(Array.length(after))->Expect.toBe(3)
        before->Array.forEachWithIndex(
          (old, depth) => {
            let new = Array.getUnsafe(after, depth)
            t->expect(new === old)->Expect.toBeFalsy
            t->expect(new.keys === old.keys)->Expect.toBeTruthy
            if Node.isLeaf(old) {
              t->expect(new.values === old.values)->Expect.toBeFalsy
              t->expect(new.links === old.links)->Expect.toBeTruthy
            } else {
              t->expect(new.values === old.values)->Expect.toBeTruthy
              t->expect(new.links === old.links)->Expect.toBeFalsy
              t->expect(Node.counts(new))->Expect.toEqual(Node.counts(old))
              // Every child but the one on the path is the same node as before.
              let newChildren = Node.children(new)
              let changed =
                Node.children(old)->Array.filterWithIndex(
                  (child, index) => child !== Array.getUnsafe(newChildren, index),
                )
              t->expect(Array.length(changed))->Expect.toBe(1)
            }
          },
        )
        t->expect(Tree.get(overwritten, key))->Expect.toEqual(Some(-1))
        t->expect(Tree.get(tall, key))->Expect.toEqual(Some(key * 10))
      },
    )

    test("setting a key to the value it already holds returns the same tree", t => {
      t->expect(Tree.set(tall, key, key * 10) === tall)->Expect.toBeTruthy
      let boxed = Tree.fromArray(~id, [(1, [1]), (2, [2])])
      let held = Tree.get(boxed, 2)->Option.getOrThrow
      t->expect(Tree.set(boxed, 2, held) === boxed)->Expect.toBeTruthy
      // An equal value that is a different object is still an overwrite.
      t->expect(Tree.set(boxed, 2, [2]) === boxed)->Expect.toBeFalsy
    })

    test("an insertion or removal that needs no rebalancing reuses the separators above it", t => {
      // Make room first: `fromArray` fills leaves, so the first insertion into one splits it.
      let roomy = Tree.remove(tall, key)
      [Tree.set(roomy, key, -1), Tree.remove(roomy, key + 1)]->Array.forEach(
        edited => {
          Tree.checkInvariants(edited)
          let before = pathTo(roomy, key)
          let after = pathTo(edited, key)
          before->Array.forEachWithIndex(
            (old, depth) => {
              let new = Array.getUnsafe(after, depth)
              if Node.isLeaf(old) {
                t->expect(new.keys === old.keys)->Expect.toBeFalsy
              } else {
                t->expect(new.keys === old.keys)->Expect.toBeTruthy
                t->expect(Node.size(new) == Node.size(old))->Expect.toBeFalsy
              }
            },
          )
        },
      )
    })

    test("a diff after an overwrite compares one leaf's values and nothing else", t => {
      let overwritten = Tree.set(tall, key, -1)
      let (result, compared) = runDiff(tall, overwritten)
      t
      ->expect(result)
      ->Expect.toEqual({
        onlyLeft: [],
        onlyRight: [],
        different: [(key, key * 10, -1)],
      })
      t->expect(compared)->Expect.Int.toBeLessThanOrEqual(max)
      // Every other child of every node on the path is skipped whole.
      t
      ->expect(Tree.sharedSubtreeCount(tall, overwritten))
      ->Expect.toBe(
        pathTo(tall, key)->Array.reduce(
          0,
          (total, node) => Node.isLeaf(node) ? total : total + Node.width(node) - 1,
        ),
      )
    })
  })

  describe(`${Config.name}: diff across shared nodes`, () => {
    let tall: tree = Tree.fromArray(~id, Belt.Array.makeBy(max * max * 3, key => (key * 10, key)))
    let last = (max * max * 3 - 1) * 10

    test(
      "differences that follow a run of shared nodes are reported, under changed separators",
      t => {
        // A split in the first leaf changes the separators of the node above it, so the cursors
        // take over there and then skip that node's other leaves, which are shared. The later
        // edits lie beyond them, under that node and under others.
        let edited =
          tall
          ->Tree.set(5, -1)
          ->Tree.set((max * max - 1) * 10, -2)
          ->Tree.remove((max * max - 2) * 10)
          ->Tree.set(max * max * 10 + 5, -3)
          ->Tree.set(last, -4)
          ->Tree.set(last + 10, -5)
        Tree.checkInvariants(edited)
        let separatorsAbove = (tree: tree) => Array.getUnsafe(pathTo(tree, 5), 1).keys
        t->expect(separatorsAbove(edited) === separatorsAbove(tall))->Expect.toBeFalsy
        let (result, compared) = runDiff(tall, edited)
        t
        ->expect(result)
        ->Expect.toEqual({
          onlyLeft: [((max * max - 2) * 10, max * max - 2)],
          onlyRight: [(5, -1), (max * max * 10 + 5, -3), (last + 10, -5)],
          different: [((max * max - 1) * 10, max * max - 1, -2), (last, max * max * 3 - 1, -4)],
        })
        // Four leaves were edited (two of them split); nothing else is looked at.
        t->expect(compared)->Expect.Int.toBeLessThanOrEqual(4 * max)
        t->expect(Tree.sharedSubtreeCount(tall, edited))->Expect.Int.toBeGreaterThan(max)
        expectDiffBothWays(t, tall, edited)
      },
    )

    test("a single difference at the very end, after everything else is shared", t => {
      [
        Tree.set(tall, last + 10, -1),
        Tree.remove(tall, last),
        Tree.set(tall, last, -1),
      ]->Array.forEach(
        edited => {
          expectDiffBothWays(t, tall, edited)
          let (result, _) = runDiff(tall, edited)
          t
          ->expect(
            Array.length(result.onlyLeft) +
            Array.length(result.onlyRight) +
            Array.length(result.different),
          )
          ->Expect.toBe(1)
        },
      )
    })

    test("trees of different heights that share their leftmost leaves", t => {
      // Appending to a small tree until it is taller leaves its first leaves in place.
      let short: tree = Tree.fromArray(~id, Belt.Array.makeBy(max * 3, key => (key, key)))
      let grown = ref(short)
      for key in max * 3 to max * max * 2 {
        grown := Tree.set(grown.contents, key, -key)
      }
      let grown = Tree.set(grown.contents, max * 3 - 1, -7)
      t
      ->expect(Node.height(rootOf(grown), 0))
      ->Expect.Int.toBeGreaterThan(Node.height(rootOf(short), 0))
      t->expect(Tree.sharedSubtreeCount(short, grown))->Expect.Int.toBeGreaterThanOrEqual(2)
      t->expect(Tree.sharedSubtreeCount(grown, short))->Expect.Int.toBeGreaterThanOrEqual(2)
      expectDiffBothWays(t, short, grown)
      let (result, compared) = runDiff(short, grown)
      t->expect(result.different)->Expect.toEqual([(max * 3 - 1, max * 3 - 1, -7)])
      t->expect(Array.length(result.onlyRight))->Expect.toBe(max * max * 2 + 1 - max * 3)
      t->expect(compared)->Expect.Int.toBeLessThanOrEqual(max)
    })

    test("every pair of trees from a history of edits", t => {
      let random = TestSupport.Random.make(8675309.0)
      let versions = [tall]
      let current = ref(tall)
      for step in 1 to 12 {
        for _ in 1 to step * 3 {
          let key = TestSupport.Random.nextInt(random, max * max * 3 + 50) * 10
          current :=
            switch mod(TestSupport.Random.nextInt(random, 1000), 3) {
            | 0 => Tree.remove(current.contents, key)
            | 1 => Tree.set(current.contents, key, -step)
            | _ => Tree.set(current.contents, key + 5, step)
            }
        }
        Tree.checkInvariants(current.contents)
        Array.push(versions, current.contents)
      }
      versions->Array.forEach(
        left => versions->Array.forEach(right => expectDiffBothWays(t, left, right)),
      )
    })
  })
}

module Focused8 = Focused(
  BTree8,
  {
    let name = "BTree, nodes of 8"
  },
)

module Focused16 = Focused(
  BTree16,
  {
    let name = "BTree, nodes of 16"
  },
)

module Focused32 = Focused(
  BTree32,
  {
    let name = "BTree, nodes of 32"
  },
)
