/***
Tests `AvlNode.checkInvariants` directly, on nodes constructed by hand. Every other AVL test
relies on it to catch a structural bug in `AvlNode.set`/`remove`, which is only sound if it
actually rejects a broken tree -- and accepts a valid but unusual one.
*/

open Vitest

let intCompare = (a: int, b: int): int => a - b

let check = (tree: AvlNode.tree<int, int>): unit =>
  AvlNode.checkInvariants(tree, ~compare=intCompare)

/** A node whose cached `height` and `size` are correct for the children it is given. */
let node = (~left=?, ~right=?, key: int): AvlNode.t<int, int> => {
  let height = (tree: AvlNode.tree<int, int>) =>
    switch tree {
    | None => 0
    | Some(child) => child.height
    }
  {
    key,
    value: key,
    height: max(height(left), height(right)) + 1,
    size: AvlNode.size(left) + AvlNode.size(right) + 1,
    left,
    right,
  }
}

describe("AvlNode.checkInvariants: valid trees pass", () => {
  test("the empty tree", t => {
    t->expect(() => check(None))->Expect.not->Expect.toThrow
  })

  test("a single node", t => {
    t->expect(() => check(Some(node(1))))->Expect.not->Expect.toThrow
  })

  test("a perfectly balanced tree", t => {
    let tree = node(
      ~left=node(~left=node(1), ~right=node(3), 2),
      ~right=node(~left=node(5), ~right=node(7), 6),
      4,
    )
    t->expect(() => check(Some(tree)))->Expect.not->Expect.toThrow
  })

  test("siblings whose heights differ by 2, the most this tree allows", t => {
    let tree = node(~left=node(~left=node(1), 2), 3)
    t->expect(() => check(Some(tree)))->Expect.not->Expect.toThrow
  })
})

describe("AvlNode.checkInvariants: broken trees are rejected", () => {
  test("a left child with a greater key", t => {
    t->expect(() => check(Some(node(~left=node(5), 3))))->Expect.toThrow
  })

  test("a right child with a smaller key", t => {
    t->expect(() => check(Some(node(~right=node(1), 3))))->Expect.toThrow
  })

  test("a duplicate key", t => {
    t->expect(() => check(Some(node(~right=node(3), 3))))->Expect.toThrow
  })

  test("a key in order with its parent but not with an ancestor further up", t => {
    // 5 is correctly to the right of 2, but sits in the left subtree of 4.
    let tree = node(~left=node(~right=node(5), 2), ~right=node(6), 4)
    t->expect(() => check(Some(tree)))->Expect.toThrow
  })

  test("siblings whose heights differ by 3", t => {
    let tree = node(~left=node(~left=node(~left=node(1), 2), 3), 4)
    t->expect(() => check(Some(tree)))->Expect.toThrow
  })

  test("a wrong cached height", t => {
    t->expect(() => check(Some({...node(~left=node(1), 2), height: 3})))->Expect.toThrow
  })

  test("a wrong cached size", t => {
    t->expect(() => check(Some({...node(~left=node(1), 2), size: 3})))->Expect.toThrow
  })

  test("a violation deep in the tree, not just at the root", t => {
    let broken = {...node(5), size: 2}
    let tree = node(
      ~left=node(~left=node(1), ~right=node(3), 2),
      ~right=node(~left=broken, ~right=node(7), 6),
      4,
    )
    t->expect(() => check(Some(tree)))->Expect.toThrow
  })
})
