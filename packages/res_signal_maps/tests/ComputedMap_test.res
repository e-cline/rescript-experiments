open Vitest
open ResSignals

let id = TestSupport.intId

/**
The tests for any tree's maps: run below over the package's own (`BTree`), and over `AvlTree` and
`ChunkTree` through `SignalMap.Make`.
*/
module Suite = (
  Tree: ResTrees.SortedMap.S,
  Maps: SignalMap.Maps with type tree<'k, 'v, 'id> = Tree.t<'k, 'v, 'id>,
  Name: {
    let name: string
  },
) => {
  module AtomMap = Maps.AtomMap
  module ComputedMap = Maps.ComputedMap

  describe(Name.name, () => {
    describe("ComputedMap: chaining stays incremental", () => {
      test(
        "filter -> mapValues -> count updates incrementally end to end",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1), (2, 2), (3, 3), (4, 4)])
          let evens =
            AtomMap.asComputedMap(m)->ComputedMap.filter((_key, value) => mod(value, 2) === 0)
          let calls = ref(0)
          let scaled = evens->ComputedMap.mapValues(
            (_key, value) => {
              calls := calls.contents + 1
              value * 100
            },
          )
          let count = scaled->ComputedMap.count

          t->expect(ComputedMap.toArray(scaled))->Expect.toEqual([(2, 200), (4, 400)])
          t->expect(Signal.get(count))->Expect.toBe(2)
          let callsAfterFirstBuild = calls.contents

          // A value change that keeps 6 even: mapValues re-runs only for key 2;
          // count is unaffected (still 2 evens).
          AtomMap.setValue(m, 2, 6)->ignore
          t->expect(ComputedMap.toArray(scaled))->Expect.toEqual([(2, 600), (4, 400)])
          t->expect(Signal.get(count))->Expect.toBe(2)
          t->expect(calls.contents)->Expect.toBe(callsAfterFirstBuild + 1)

          // An odd-to-even flip: a brand new entry flows all the way through to count.
          AtomMap.setValue(m, 1, 10)->ignore
          t->expect(ComputedMap.toArray(scaled))->Expect.toEqual([(1, 1000), (2, 600), (4, 400)])
          t->expect(Signal.get(count))->Expect.toBe(3)
        },
      )

      test(
        "ComputedMap.get is itself a reactive signal (usable inside another Computed)",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1), (2, 2)])
          let doubled = AtomMap.mapValues(m, (_key, value) => value * 2)
          let total = Computed.make(
            () => doubled->ComputedMap.get->Tree.reduce(0, (acc, _key, value) => acc + value),
          )
          t->expect(Signal.get(total))->Expect.toBe(6)
          AtomMap.setValue(m, 3, 3)->ignore
          t->expect(Signal.get(total))->Expect.toBe(12)
        },
      )
    })
  })
}

module BTreeSuite = Suite(
  MapTree.BTree,
  TestSupport.BTreeMaps,
  {
    let name = "BTree"
  },
)

module AvlTreeSuite = Suite(
  ResTrees.AvlTree,
  TestSupport.AvlTreeMaps,
  {
    let name = "AvlTree"
  },
)

module ChunkTreeSuite = Suite(
  ResTrees.ChunkTree,
  TestSupport.ChunkTreeMaps,
  {
    let name = "ChunkTree"
  },
)
