/***
`ChunkTree` at each leaf size through the shared conformance suite, then what that suite cannot
see from outside: where leaves split, merge and borrow, that an overwrite shares the leaf's
`keys`, how many comparator calls a diff makes, and that `checkInvariants` rejects broken trees.
*/

open Vitest

// `maxComparedAfter25Edits` counts calls to `valueEqual`. `ChunkDiff` takes two values that are
// `===` to be equal without calling it, and insertions and removals leave every surviving value
// as it was, so the count observed in that test is 0 at every leaf size, and the limit of 1 says
// so. That makes it a weaker measure here than it is for `AvlTree`. Measured separately with
// values that are never `===` (`NaN`), the same 25 edits make a diff look at up to 142 pairs of
// entries with leaves of 8, 292 with leaves of 16 and 590 with leaves of 32, against `AvlTree`'s
// 221; and call the comparator at most 25 times at any of the three sizes, against 234. The
// comparator-call tests further down hold it to that.

module Suite8 = Conformance.Make(
  ChunkTree.Make({
    let maxLeafSize = 8
  }),
  {
    let name = "ChunkTree, leaves of 8"
    let maxComparedAfter25Edits = 1
  },
)
module Suite16 = Conformance.Make(
  ChunkTree,
  {
    let name = "ChunkTree (leaves of 16)"
    let maxComparedAfter25Edits = 1
  },
)
module Suite32 = Conformance.Make(
  ChunkTree.Make({
    let maxLeafSize = 32
  }),
  {
    let name = "ChunkTree, leaves of 32"
    let maxComparedAfter25Edits = 1
  },
)

// Not sizes anyone would use: the smallest the tree allows, and an odd one, where the split and
// the minimum round differently.
module Suite2 = Conformance.Make(
  ChunkTree.Make({
    let maxLeafSize = 2
  }),
  {
    let name = "ChunkTree, leaves of 2"
    let maxComparedAfter25Edits = 1
  },
)
module Suite5 = Conformance.Make(
  ChunkTree.Make({
    let maxLeafSize = 5
  }),
  {
    let name = "ChunkTree, leaves of 5"
    let maxComparedAfter25Edits = 1
  },
)

type node = ChunkNode.t<int, int>

let compare = (a: int, b: int): int => a - b

/** `count` keys from `start`, 10 apart, leaving room to insert between any two. */
let spaced = (start: int, count: int): array<int> =>
  Belt.Array.makeBy(count, index => start + index * 10)

let leaf = (keys: array<int>): node => ChunkNode.makeLeaf(keys, keys->Array.map(key => -key))

/** An internal node over two subtrees, with the separator and cached fields it should have. */
let join = (left: node, right: node): node =>
  ChunkNode.create(left, ChunkNode.minLeaf(right).key, right)

let check = (node: node, ~max: int): unit => ChunkNode.checkInvariants(Some(node), ~compare, ~max)

let keysOf = (node: node): array<int> => {
  let keys = []
  ChunkNode.forEach(node, (key, _) => Array.push(keys, key))
  keys
}

let get = (node: node, key: int): option<int> => {
  let leaf = ChunkNode.findLeaf(node, key, ~compare)
  let index = ChunkNode.search(leaf.keys, key, ~compare)
  index >= 0 ? Some(Array.getUnsafe(leaf.values, index)) : None
}

let without = (keys: array<int>, key: int): array<int> => keys->Array.filter(k => k != key)

[8, 16, 32, 5]->Array.forEach(max => {
  let min = max / 2
  let sizeName = `leaves of ${Int.toString(max)}`

  describe(`ChunkNode, ${sizeName}: splitting`, () => {
    test(
      "a leaf takes entries up to the maximum without splitting",
      t => {
        let node = ref(leaf([0]))
        for index in 1 to max - 1 {
          node := ChunkNode.set(node.contents, index * 10, 0, ~compare, ~max)
          check(node.contents, ~max)
        }
        t->expect(node.contents.height)->Expect.toBe(1)
        t->expect(node.contents.size)->Expect.toBe(max)
      },
    )

    test(
      "inserting into a full leaf, at any position, splits it evenly",
      t => {
        let full = leaf(spaced(0, max))
        for position in 0 to max {
          let key = position * 10 - 5
          let split = ChunkNode.set(full, key, 1, ~compare, ~max)
          check(split, ~max)
          t->expect(split.height)->Expect.toBe(2)
          t->expect(split.size)->Expect.toBe(max + 1)
          t->expect(split.left.size)->Expect.toBe((max + 2) / 2)
          t->expect(split.right.size)->Expect.toBe((max + 1) / 2)
          t->expect(split.key)->Expect.toBe(Array.getUnsafe(split.right.keys, 0))
          t
          ->expect(keysOf(split))
          ->Expect.toEqual(
            Array.concat(spaced(0, max), [key])->Array.toSorted((a, b) => Int.toFloat(a - b)),
          )
          t->expect(get(split, key))->Expect.toEqual(Some(1))
        }
        // The full leaf itself is untouched.
        t->expect(full.keys)->Expect.toEqual(spaced(0, max))
      },
    )
  })

  describe(`ChunkNode, ${sizeName}: underflow`, () => {
    let removeAndCheck = (t, node: node, key: int): node => {
      let result = ChunkNode.removeFrom(node, key, ~compare, ~max)
      check(result, ~max)
      t->expect(keysOf(result))->Expect.toEqual(without(keysOf(node), key))
      // The tree removed from is untouched.
      check(node, ~max)
      result
    }

    test(
      "a leaf at the minimum loses an entry without help if it is the root",
      t => {
        let result = removeAndCheck(t, leaf(spaced(0, min)), 0)
        t->expect(result.height)->Expect.toBe(1)
      },
    )

    test(
      "two leaves at the minimum merge into one, whichever is removed from",
      t => {
        let node = join(leaf(spaced(0, min)), leaf(spaced(1000, min)))
        check(node, ~max)
        [0, (min - 1) * 10, 1000, 1000 + (min - 1) * 10]->Array.forEach(
          key => {
            let result = removeAndCheck(t, node, key)
            t->expect(result.height)->Expect.toBe(1)
            t->expect(result.size)->Expect.toBe(2 * min - 1)
          },
        )
      },
    )

    test(
      "a leaf at the minimum borrows from a neighbour that has entries to spare",
      t => {
        for spare in 1 to max - min {
          let onRight = join(leaf(spaced(0, min)), leaf(spaced(1000, min + spare)))
          let onLeft = join(leaf(spaced(0, min + spare)), leaf(spaced(1000, min)))
          check(onRight, ~max)
          check(onLeft, ~max)
          let total = 2 * min + spare - 1
          if total >= max {
            [(onRight, 0), (onLeft, 1000)]->Array.forEach(
              ((node, key)) => {
                let result = removeAndCheck(t, node, key)
                t->expect(result.height)->Expect.toBe(2)
                t->expect(result.left.size + result.right.size)->Expect.toBe(total)
                t->expect(abs(result.left.size - result.right.size))->Expect.Int.toBeLessThan(2)
                t->expect(result.key)->Expect.toBe(Array.getUnsafe(result.right.keys, 0))
              },
            )
          }
        }
      },
    )

    test(
      "the neighbour is found at the near edge of a taller sibling",
      t => {
        [min, min + 1, max]->Array.forEach(
          neighbourSize => {
            // Underfull leaf on the left, its neighbour the first leaf of a subtree 3 tall.
            let tallRight = join(
              join(leaf(spaced(1000, neighbourSize)), leaf(spaced(2000, max))),
              leaf(spaced(3000, max)),
            )
            let node = join(leaf(spaced(0, min)), tallRight)
            check(node, ~max)
            let result = removeAndCheck(t, node, 0)
            let merges = min - 1 + neighbourSize < max
            t->expect(result.height)->Expect.toBe(merges ? 3 : 4)
            // Everything but the path to the neighbour is still shared.
            t->expect(merges ? result.right : result.right.right)->Expect.toBe(tallRight.right)

            // And the mirror image.
            let tallLeft = join(
              leaf(spaced(0, max)),
              join(leaf(spaced(1000, max)), leaf(spaced(2000, neighbourSize))),
            )
            let node = join(tallLeft, leaf(spaced(3000, min)))
            check(node, ~max)
            let result = removeAndCheck(t, node, 3000)
            t->expect(result.height)->Expect.toBe(merges ? 3 : 4)
            t->expect(merges ? result.left : result.left.left)->Expect.toBe(tallLeft.left)
          },
        )
      },
    )

    test(
      "removing a subtree's smallest key leaves a separator the tree no longer holds",
      t => {
        let node = join(leaf(spaced(0, max)), leaf(spaced(1000, max)))
        let result = removeAndCheck(t, node, 1000)
        t->expect(result.key)->Expect.toBe(1000)
        t->expect(get(result, 1000))->Expect.toBeNone
        t->expect(get(result, 1010))->Expect.toEqual(Some(-1010))
      },
    )
  })

  describe(`ChunkNode, ${sizeName}: sharing`, () => {
    let keys = spaced(0, 500)
    let root =
      ChunkNode.fromSortedArrays(keys, keys->Array.map(key => -key), ~max)->Option.getOrThrow

    test(
      "fromSortedArrays fills every leaf to within the bounds, at every size",
      _ => {
        for count in 1 to 300 {
          let keys = spaced(0, count)
          ChunkNode.checkInvariants(ChunkNode.fromSortedArrays(keys, keys, ~max), ~compare, ~max)
        }
      },
    )

    test(
      "an overwrite shares the leaf's keys and copies its values",
      t => {
        keys->Array.forEach(
          key => {
            let before = ChunkNode.findLeaf(root, key, ~compare)
            let edited = ChunkNode.set(root, key, 1, ~compare, ~max)
            let after = ChunkNode.findLeaf(edited, key, ~compare)
            t->expect(after === before)->Expect.toBeFalsy
            t->expect(after.keys === before.keys)->Expect.toBeTruthy
            t->expect(after.values === before.values)->Expect.toBeFalsy
            t->expect(get(root, key))->Expect.toEqual(Some(-key))
            t->expect(get(edited, key))->Expect.toEqual(Some(1))
            t->expect(edited.height)->Expect.toBe(root.height)
          },
        )
      },
    )

    test(
      "setting a key to the value it holds returns the same node",
      t => {
        keys->Array.forEach(
          key =>
            t->expect(ChunkNode.set(root, key, -key, ~compare, ~max) === root)->Expect.toBeTruthy,
        )
      },
    )

    // How many times a diff of the two trees calls the comparator.
    let comparisonsIn = (left: node, right: node): int => {
      let count = ref(0)
      ChunkDiff.run(
        Some(left),
        Some(right),
        ~compare=(a, b) => {
          count := count.contents + 1
          a - b
        },
        ~valueEqual=(a, b) => a == b,
        ~onlyLeft=(_, _) => (),
        ~onlyRight=(_, _) => (),
        ~different=(_, _, _) => (),
        ~onSharedSubtreeSkipped=() => (),
      )
      count.contents
    }

    test(
      "a diff across overwrites never calls the comparator",
      t => {
        let edited =
          [0, 10, 770, 2500, 4990]->Array.reduce(
            root,
            (node, key) => ChunkNode.set(node, key, 1, ~compare, ~max),
          )
        t->expect(comparisonsIn(root, edited))->Expect.toBe(0)
        t->expect(comparisonsIn(edited, root))->Expect.toBe(0)
      },
    )

    test(
      "a diff across one insertion or removal calls it a handful of times",
      t => {
        keys->Array.forEach(
          key => {
            let inserted = ChunkNode.set(root, key + 5, 1, ~compare, ~max)
            let removed = ChunkNode.removeFrom(root, key, ~compare, ~max)
            // One call where the two leaves stop holding the same keys, then one per separator
            // that a split, merge or rotation moved, and per key of a leaf that was rebuilt.
            [inserted, removed]->Array.forEach(
              edited => {
                t->expect(comparisonsIn(root, edited))->Expect.Int.toBeLessThan(2 * max + 8)
                t->expect(comparisonsIn(edited, root))->Expect.Int.toBeLessThan(2 * max + 8)
              },
            )
          },
        )
      },
    )
  })

  describe(`ChunkNode.checkInvariants, ${sizeName}: broken trees are rejected`, () => {
    let rejects = (t, node: node) => t->expect(() => check(node, ~max))->Expect.toThrow
    let low = leaf(spaced(0, max))
    let high = leaf(spaced(1000, max))
    let valid = join(low, high)

    test(
      "the trees these are derived from are valid",
      t => {
        t->expect(() => check(valid, ~max))->Expect.not->Expect.toThrow
        t->expect(() => check(join(valid, join(high, high)), ~max))->Expect.toThrow
      },
    )

    test(
      "leaf occupancy",
      t => {
        rejects(t, leaf(spaced(0, max + 1)))
        rejects(t, join(leaf(spaced(0, min - 1)), high))
        rejects(t, join(low, leaf(spaced(1000, min - 1))))
        rejects(t, {...low, keys: [], values: [], size: 0})
      },
    )

    test(
      "a leaf's own fields",
      t => {
        rejects(t, {...low, size: max - 1})
        rejects(t, {...low, values: Array.slice(low.values, ~start=1)})
        rejects(t, {...low, key: 10})
        rejects(t, leaf(Array.concat([10, 0], spaced(20, max - 2))))
        rejects(t, leaf(Array.concat([0, 0], spaced(20, max - 2))))
      },
    )

    test(
      "key order across leaves, and separators",
      t => {
        rejects(t, ChunkNode.create(high, 1000, low))
        // Too high for the right subtree, too low for the left.
        rejects(t, {...valid, key: 1010})
        rejects(t, {...valid, key: (max - 1) * 10})
        // A separator that is no key of the tree's, but still divides it, is fine.
        t->expect(() => check({...valid, key: 500}, ~max))->Expect.not->Expect.toThrow
        // A key in the right place under its parent but the wrong side of its grandparent.
        let middle = leaf(spaced(400, max))
        rejects(t, ChunkNode.create(low, 1000, ChunkNode.create(middle, 1000, high)))
        rejects(t, ChunkNode.create(ChunkNode.create(low, 400, middle), 300, high))
      },
    )

    test(
      "cached sizes and heights, balance, and entries in an internal node",
      t => {
        rejects(t, {...valid, size: valid.size + 1})
        rejects(t, {...valid, height: 3})
        rejects(t, {...valid, keys: [1], values: [1]})
        let deep = (start: int) => join(leaf(spaced(start, max)), leaf(spaced(start + 500, max)))
        let threeTall = join(deep(1000), leaf(spaced(2000, max)))
        // Heights 1 and 3 are within bounds; 1 and 4 are not.
        t->expect(() => check(join(low, threeTall), ~max))->Expect.not->Expect.toThrow
        rejects(t, join(low, join(threeTall, leaf(spaced(3000, max)))))
      },
    )
  })
})
