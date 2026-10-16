/***
Tests `MutableChunkTree`: that each function forwards to `ChunkTree` correctly, and the things
specific to mutability -- shared references, and snapshots that stay put.
*/

open Vitest

let id = TestSupport.intId

describe("MutableChunkTree", () => {
  test("fromArray seeds the tree; duplicate keys keep the later pair", t => {
    let tree = MutableChunkTree.fromArray(~id, [(2, "b"), (1, "a"), (3, "c"), (1, "a-again")])
    t->expect(MutableChunkTree.size(tree))->Expect.toBe(3)
    t->expect(MutableChunkTree.toArray(tree))->Expect.toEqual([(1, "a-again"), (2, "b"), (3, "c")])
  })

  test("every read operation behaves as expected on an empty tree", t => {
    let tree = MutableChunkTree.make(~id)
    t->expect(MutableChunkTree.size(tree))->Expect.toBe(0)
    t->expect(MutableChunkTree.isEmpty(tree))->Expect.toBeTruthy
    t->expect(MutableChunkTree.get(tree, 1))->Expect.toBeNone
    t->expect(MutableChunkTree.has(tree, 1))->Expect.toBeFalsy
    t->expect(MutableChunkTree.minKey(tree))->Expect.toBeNone
    t->expect(MutableChunkTree.maxKey(tree))->Expect.toBeNone
    t->expect(MutableChunkTree.getAt(tree, 0))->Expect.toBeNone
    t->expect(MutableChunkTree.toArray(tree))->Expect.toEqual([])

    // Removing from an empty tree is a no-op, not an error.
    MutableChunkTree.remove(tree, 1)
    t->expect(MutableChunkTree.isEmpty(tree))->Expect.toBeTruthy
  })

  test("set and remove change the tree in place", t => {
    let tree = MutableChunkTree.make(~id)
    for key in 0 to 99 {
      MutableChunkTree.set(tree, key, key * 10)
    }
    MutableChunkTree.set(tree, 50, -1)
    MutableChunkTree.remove(tree, 0)
    MutableChunkTree.checkInvariants(tree)

    t->expect(MutableChunkTree.size(tree))->Expect.toBe(99)
    t->expect(MutableChunkTree.get(tree, 50))->Expect.toEqual(Some(-1))
    t->expect(MutableChunkTree.has(tree, 0))->Expect.toBeFalsy
    t->expect(MutableChunkTree.minKey(tree))->Expect.toEqual(Some(1))
    t->expect(MutableChunkTree.maxKey(tree))->Expect.toEqual(Some(99))
    t->expect(MutableChunkTree.getAt(tree, 0))->Expect.toEqual(Some((1, 10)))
    t->expect(MutableChunkTree.indexOf(tree, 99))->Expect.toEqual(Some(98))
    t->expect(MutableChunkTree.keysArray(tree))->Expect.toEqual(Belt.Array.makeBy(99, i => i + 1))
    t->expect(Array.length(MutableChunkTree.valuesArray(tree)))->Expect.toBe(99)
    t->expect(MutableChunkTree.reduce(tree, 0, (count, _, _) => count + 1))->Expect.toBe(99)
    let visited = []
    MutableChunkTree.forEach(tree, (key, _) => Array.push(visited, key))
    t->expect(visited)->Expect.toEqual(MutableChunkTree.keysArray(tree))
  })

  test("two bindings to the same tree observe each other's writes", t => {
    let tree = MutableChunkTree.make(~id)
    let alias = tree
    MutableChunkTree.set(tree, 1, "one")
    t->expect(MutableChunkTree.get(alias, 1))->Expect.toEqual(Some("one"))
    MutableChunkTree.remove(alias, 1)
    t->expect(MutableChunkTree.isEmpty(tree))->Expect.toBeTruthy
  })

  test("a snapshot is unaffected by later edits, and diffs against a later one", t => {
    let tree = MutableChunkTree.fromArray(~id, Belt.Array.makeBy(100, key => (key, key)))
    let before = MutableChunkTree.snapshot(tree)
    MutableChunkTree.set(tree, 5, -5)
    MutableChunkTree.remove(tree, 6)
    MutableChunkTree.set(tree, 200, 200)
    let after = MutableChunkTree.snapshot(tree)

    t->expect(ChunkTree.size(before))->Expect.toBe(100)
    t->expect(ChunkTree.get(before, 5))->Expect.toEqual(Some(5))

    let changes = []
    ChunkTree.diff(
      before,
      after,
      ~onlyLeft=(key, _) => Array.push(changes, `removed ${Int.toString(key)}`),
      ~onlyRight=(key, _) => Array.push(changes, `added ${Int.toString(key)}`),
      ~different=(key, _, _) => Array.push(changes, `changed ${Int.toString(key)}`),
    )
    t->expect(changes)->Expect.toEqual(["changed 5", "removed 6", "added 200"])
  })
})
