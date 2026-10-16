/***
Tests `MutableAvlTree`: that each function forwards to `AvlTree` correctly, and the things
specific to mutability -- shared references, and snapshots that stay put.
*/

open Vitest

let id = TestSupport.intId

describe("MutableAvlTree", () => {
  test("fromArray seeds the tree; duplicate keys keep the later pair", t => {
    let tree = MutableAvlTree.fromArray(~id, [(2, "b"), (1, "a"), (3, "c"), (1, "a-again")])
    t->expect(MutableAvlTree.size(tree))->Expect.toBe(3)
    t->expect(MutableAvlTree.toArray(tree))->Expect.toEqual([(1, "a-again"), (2, "b"), (3, "c")])
  })

  test("every read operation behaves as expected on an empty tree", t => {
    let tree = MutableAvlTree.make(~id)
    t->expect(MutableAvlTree.size(tree))->Expect.toBe(0)
    t->expect(MutableAvlTree.isEmpty(tree))->Expect.toBeTruthy
    t->expect(MutableAvlTree.get(tree, 1))->Expect.toBeNone
    t->expect(MutableAvlTree.has(tree, 1))->Expect.toBeFalsy
    t->expect(MutableAvlTree.minKey(tree))->Expect.toBeNone
    t->expect(MutableAvlTree.maxKey(tree))->Expect.toBeNone
    t->expect(MutableAvlTree.getAt(tree, 0))->Expect.toBeNone
    t->expect(MutableAvlTree.toArray(tree))->Expect.toEqual([])

    // Removing from an empty tree is a no-op, not an error.
    MutableAvlTree.remove(tree, 1)
    t->expect(MutableAvlTree.isEmpty(tree))->Expect.toBeTruthy
  })

  test("set and remove change the tree in place", t => {
    let tree = MutableAvlTree.make(~id)
    for key in 0 to 99 {
      MutableAvlTree.set(tree, key, key * 10)
    }
    MutableAvlTree.set(tree, 50, -1)
    MutableAvlTree.remove(tree, 0)
    MutableAvlTree.checkInvariants(tree)

    t->expect(MutableAvlTree.size(tree))->Expect.toBe(99)
    t->expect(MutableAvlTree.get(tree, 50))->Expect.toEqual(Some(-1))
    t->expect(MutableAvlTree.has(tree, 0))->Expect.toBeFalsy
    t->expect(MutableAvlTree.minKey(tree))->Expect.toEqual(Some(1))
    t->expect(MutableAvlTree.maxKey(tree))->Expect.toEqual(Some(99))
    t->expect(MutableAvlTree.getAt(tree, 0))->Expect.toEqual(Some((1, 10)))
    t->expect(MutableAvlTree.indexOf(tree, 99))->Expect.toEqual(Some(98))
    t->expect(MutableAvlTree.keysArray(tree))->Expect.toEqual(Belt.Array.makeBy(99, i => i + 1))
    t->expect(Array.length(MutableAvlTree.valuesArray(tree)))->Expect.toBe(99)
    t->expect(MutableAvlTree.reduce(tree, 0, (count, _, _) => count + 1))->Expect.toBe(99)
    let visited = []
    MutableAvlTree.forEach(tree, (key, _) => Array.push(visited, key))
    t->expect(visited)->Expect.toEqual(MutableAvlTree.keysArray(tree))
  })

  test("two bindings to the same tree observe each other's writes", t => {
    let tree = MutableAvlTree.make(~id)
    let alias = tree
    MutableAvlTree.set(tree, 1, "one")
    t->expect(MutableAvlTree.get(alias, 1))->Expect.toEqual(Some("one"))
    MutableAvlTree.remove(alias, 1)
    t->expect(MutableAvlTree.isEmpty(tree))->Expect.toBeTruthy
  })

  test("a snapshot is unaffected by later edits, and diffs against a later one", t => {
    let tree = MutableAvlTree.fromArray(~id, Belt.Array.makeBy(100, key => (key, key)))
    let before = MutableAvlTree.snapshot(tree)
    MutableAvlTree.set(tree, 5, -5)
    MutableAvlTree.remove(tree, 6)
    MutableAvlTree.set(tree, 200, 200)
    let after = MutableAvlTree.snapshot(tree)

    t->expect(AvlTree.size(before))->Expect.toBe(100)
    t->expect(AvlTree.get(before, 5))->Expect.toEqual(Some(5))

    let changes = []
    AvlTree.diff(
      before,
      after,
      ~onlyLeft=(key, _) => Array.push(changes, `removed ${Int.toString(key)}`),
      ~onlyRight=(key, _) => Array.push(changes, `added ${Int.toString(key)}`),
      ~different=(key, _, _) => Array.push(changes, `changed ${Int.toString(key)}`),
    )
    t->expect(changes)->Expect.toEqual(["changed 5", "removed 6", "added 200"])
  })
})
