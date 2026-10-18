/***
Tests `Node.check` (what `BTree.checkInvariants` runs) on nodes built by hand. Every structural
test in this package relies on it to catch a bug in `Insert`/`Delete` at the edit that introduced
it, which is only sound if it really rejects a broken tree -- and accepts a valid but unusual one,
such as a separator that no longer equals any key.
*/

open Vitest

let compare = (a: int, b: int): int => a - b

/** Small, fixed bounds, so each test only varies the one thing it is about. */
let minSize = 2
let maxSize = 4

let check = (node: Node.t<int, int>, ~isRoot: bool=true): unit => {
  let _ = Node.check(node, ~compare, ~minSize, ~maxSize, ~isRoot, ~lower=None, ~upper=None)
}

/** A leaf whose values are its keys times ten. */
let leaf = (keys: array<int>): Node.t<int, int> => Node.leaf(keys, keys->Array.map(key => key * 10))

/** An internal node with correct cumulative counts for the children it is given. */
let internal = (separators: array<int>, children: array<Node.t<int, int>>): Node.t<int, int> => {
  let links = []
  let total = ref(0)
  children->Array.forEach(child => {
    total := total.contents + Node.size(child)
    Array.push(links, Node.Child(child))
    Array.push(links, Node.Count(total.contents))
  })
  Node.internal(separators, links)
}

describe("Node.check: valid trees pass", () => {
  test("a root leaf, which may hold a single key", t => {
    t->expect(() => check(leaf([1])))->Expect.not->Expect.toThrow
    t->expect(() => check(leaf([1, 2, 3, 4])))->Expect.not->Expect.toThrow
  })

  test("two levels, everything in order and in bounds", t => {
    let tree = internal([3], [leaf([1, 2]), leaf([3, 4])])
    t->expect(() => check(tree))->Expect.not->Expect.toThrow
  })

  test("a separator that equals no key, but still divides its neighbours correctly", t => {
    // What removing a leaf's smallest key leaves behind.
    let tree = internal([3], [leaf([1, 2]), leaf([4, 5])])
    t->expect(() => check(tree))->Expect.not->Expect.toThrow
  })

  test("three levels", t => {
    let tree = internal(
      [5],
      [internal([3], [leaf([1, 2]), leaf([3, 4])]), internal([7], [leaf([5, 6]), leaf([7, 8])])],
    )
    t->expect(() => check(tree))->Expect.not->Expect.toThrow
  })
})

describe("Node.check: broken trees are rejected", () => {
  test("keys out of order, or repeated, within a leaf", t => {
    t->expect(() => check(leaf([2, 1])))->Expect.toThrow
    t->expect(() => check(leaf([1, 1])))->Expect.toThrow
  })

  test("a leaf with a different number of values than keys", t => {
    t->expect(() => check(Node.leaf([1, 2], [10])))->Expect.toThrow
  })

  test("a leaf key on the wrong side of a separator", t => {
    t->expect(() => check(internal([3], [leaf([1, 4]), leaf([5, 6])])))->Expect.toThrow
    t->expect(() => check(internal([3], [leaf([1, 2]), leaf([2, 5])])))->Expect.toThrow
  })

  test("a key in order with its parent but not with a separator further up", t => {
    // 6 is correctly to the right of 3, but sits left of the root's separator 5.
    let tree = internal(
      [5],
      [internal([3], [leaf([1, 2]), leaf([3, 6])]), internal([7], [leaf([5, 6]), leaf([7, 8])])],
    )
    t->expect(() => check(tree))->Expect.toThrow
  })

  test("separators out of order", t => {
    t
    ->expect(() => check(internal([5, 3], [leaf([1, 2]), leaf([3, 4]), leaf([5, 6])])))
    ->Expect.toThrow
  })

  test("a non-root node below the minimum, or any node above the maximum", t => {
    t->expect(() => check(leaf([1]), ~isRoot=false))->Expect.toThrow
    t->expect(() => check(leaf([1, 2, 3, 4, 5])))->Expect.toThrow
    t->expect(() => check(internal([3], [leaf([1]), leaf([3, 4])])))->Expect.toThrow
  })

  test("a root internal node with a single child", t => {
    t->expect(() => check(internal([], [leaf([1, 2])])))->Expect.toThrow
  })

  test("a separator count that doesn't match the child count", t => {
    t->expect(() => check(internal([3, 5], [leaf([1, 2]), leaf([3, 4])])))->Expect.toThrow
  })

  test("a wrong cumulative count", t => {
    let links = [Node.Child(leaf([1, 2])), Node.Count(2), Node.Child(leaf([3, 4])), Node.Count(5)]
    t->expect(() => check(Node.internal([3], links)))->Expect.toThrow
  })

  test("leaves at different depths", t => {
    let tree = internal([5], [internal([3], [leaf([1, 2]), leaf([3, 4])]), leaf([5, 6])])
    t->expect(() => check(tree))->Expect.toThrow
  })
})
