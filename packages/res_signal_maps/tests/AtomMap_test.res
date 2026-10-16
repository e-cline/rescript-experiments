open Vitest
open ResSignals

module Effect = EffectBase.Make(Scheduler.Sync)

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
    describe("AtomMap: basic get/set/update", () => {
      test(
        "fromArray seeds the initial entries",
        t => {
          let m = AtomMap.fromArray(~id, [(1, "a"), (2, "b")])
          t->expect(AtomMap.toArray(m))->Expect.toEqual([(1, "a"), (2, "b")])
          t->expect(AtomMap.size(m))->Expect.toBe(2)
        },
      )

      test(
        "setValue/getValue/has/remove",
        t => {
          let m = AtomMap.fromArray(~id, [])
          AtomMap.setValue(m, 1, "a")->ignore
          t->expect(AtomMap.getValue(m, 1))->Expect.toEqual(Some("a"))
          t->expect(AtomMap.has(m, 1))->Expect.toBeTruthy
          AtomMap.remove(m, 1)->ignore
          t->expect(AtomMap.has(m, 1))->Expect.toBeFalsy
          t->expect(AtomMap.isEmpty(m))->Expect.toBeTruthy
        },
      )
    })

    describe("AtomMap.mapValues: incremental updates", () => {
      test(
        "reflects the mapped values",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1), (2, 2), (3, 3)])
          let doubled = AtomMap.mapValues(m, (_key, value) => value * 2)
          t->expect(ComputedMap.toArray(doubled))->Expect.toEqual([(1, 2), (2, 4), (3, 6)])
        },
      )

      test(
        "only re-runs mapFn for keys that actually changed",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1), (2, 2), (3, 3)])
          let callsAfterFirstBuild = ref([])
          let callsAfterUpdate = ref([])
          let calls = ref([])
          let doubled = AtomMap.mapValues(
            m,
            (key, value) => {
              calls := calls.contents->Belt.Array.concat([key])
              value * 2
            },
          )
          ComputedMap.get(doubled)->ignore
          callsAfterFirstBuild := calls.contents
          calls := []

          AtomMap.setValue(m, 2, 20)->ignore
          ComputedMap.get(doubled)->ignore
          callsAfterUpdate := calls.contents

          t->expect(callsAfterFirstBuild.contents)->Expect.toEqual([1, 2, 3])
          // Only key 2 changed upstream, so only key 2's mapFn should have re-run.
          t->expect(callsAfterUpdate.contents)->Expect.toEqual([2])
          t->expect(ComputedMap.toArray(doubled))->Expect.toEqual([(1, 2), (2, 40), (3, 6)])
        },
      )

      test(
        "additions and removals propagate incrementally",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1), (2, 2)])
          let doubled = AtomMap.mapValues(m, (_key, value) => value * 2)
          ComputedMap.get(doubled)->ignore
          AtomMap.setValue(m, 3, 3)->ignore
          t->expect(ComputedMap.toArray(doubled))->Expect.toEqual([(1, 2), (2, 4), (3, 6)])
          AtomMap.remove(m, 1)->ignore
          t->expect(ComputedMap.toArray(doubled))->Expect.toEqual([(2, 4), (3, 6)])
        },
      )

      test(
        "chained mapValues stays incremental end to end",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1), (2, 2), (3, 3)])
          let calls = ref([])
          let doubled = AtomMap.mapValues(m, (_key, value) => value * 2)
          let plusOne = ComputedMap.mapValues(
            doubled,
            (key, value) => {
              calls := calls.contents->Belt.Array.concat([key])
              value + 1
            },
          )
          t->expect(ComputedMap.toArray(plusOne))->Expect.toEqual([(1, 3), (2, 5), (3, 7)])
          calls := []
          AtomMap.setValue(m, 1, 100)->ignore
          t->expect(ComputedMap.toArray(plusOne))->Expect.toEqual([(1, 201), (2, 5), (3, 7)])
          t->expect(calls.contents)->Expect.toEqual([1])
        },
      )

      test(
        "falls back to a full rebuild when history can't cover the gap",
        t => {
          // historyLength: 1 means only the single most recent change is retained.
          let m = AtomMap.fromArray(~historyLength=1, ~id, [(1, 1)])
          let doubled = AtomMap.mapValues(m, (_key, value) => value * 2)
          ComputedMap.get(doubled)->ignore
          AtomMap.setValue(m, 2, 2)->ignore
          AtomMap.setValue(m, 3, 3)->ignore // overflows the 1-entry history buffer
          t->expect(ComputedMap.toArray(doubled))->Expect.toEqual([(1, 2), (2, 4), (3, 6)])
        },
      )
    })

    describe("AtomMap.filterMap / filter", () => {
      test(
        "filterMap keeps only entries mapped to Some",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1), (2, 2), (3, 3), (4, 4)])
          let evensDoubled = AtomMap.filterMap(
            m,
            (_key, value) => mod(value, 2) === 0 ? Some(value * 10) : None,
          )
          t->expect(ComputedMap.toArray(evensDoubled))->Expect.toEqual([(2, 20), (4, 40)])
        },
      )

      test(
        "an entry crossing the filter boundary is added/removed incrementally",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1), (2, 2)])
          let evens = AtomMap.filter(m, (_key, value) => mod(value, 2) === 0)
          t->expect(ComputedMap.toArray(evens))->Expect.toEqual([(2, 2)])
          AtomMap.setValue(m, 1, 10)->ignore // 1 -> 10, now passes the filter
          t->expect(ComputedMap.toArray(evens))->Expect.toEqual([(1, 10), (2, 2)])
          AtomMap.setValue(m, 2, 3)->ignore // 2 -> 3, now fails the filter
          t->expect(ComputedMap.toArray(evens))->Expect.toEqual([(1, 10)])
        },
      )
    })

    describe("AtomMap.map (rekey)", () => {
      test(
        "rekeys and remaps every entry",
        t => {
          let m = AtomMap.fromArray(~id, [(1, "a"), (2, "b")])
          let byName = AtomMap.map(m, ~id=TestSupport.stringId, (key, value) => (value, key))
          t->expect(ComputedMap.toArray(byName))->Expect.toEqual([("a", 1), ("b", 2)])
        },
      )

      test(
        "a single-write swap of two entries' keys resolves without a spurious collision",
        t => {
          let m = AtomMap.fromArray(~id, [(1, "x"), (2, "y")])
          // Rekey by value: initially {x: 1, y: 2}.
          let byValue = AtomMap.map(m, ~id=TestSupport.stringId, (key, value) => (value, key))
          t->expect(ComputedMap.toArray(byValue))->Expect.toEqual([("x", 1), ("y", 2)])
          // Swap the two values as a single write (one diff batch, with both
          // `Different` entries together) -- unlike two separate `setValue` calls
          // (even inside a `Batch.run`, which only defers *effects*, not the
          // underlying atom writes/diff epochs), this lets the remove-then-add
          // ordering within one batch resolve the swap cleanly. See
          // `internal/Rekey.res`'s own comment on per-batch processing.
          AtomMap.update(m, tree => tree->Tree.set(1, "y")->Tree.set(2, "x"))->ignore
          t->expect(ComputedMap.toArray(byValue))->Expect.toEqual([("x", 2), ("y", 1)])
        },
      )

      test(
        "a genuine collision throws, from the read that first observes it",
        t => {
          let m = AtomMap.fromArray(~id, [(1, "a"), (2, "b")])
          let byValue = AtomMap.map(m, ~id=TestSupport.stringId, (_key, value) => (value, value))
          ComputedMap.get(byValue)->ignore
          AtomMap.setValue(m, 1, "b")->ignore // doesn't throw yet: byValue is lazy
          t->expect(() => ComputedMap.get(byValue)->ignore)->Expect.toThrow
        },
      )
    })

    describe("AtomMap.fold / count / sum", () => {
      test(
        "count tracks the number of entries incrementally",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1), (2, 2)])
          let count = AtomMap.count(m)
          t->expect(Signal.get(count))->Expect.toBe(2)
          AtomMap.setValue(m, 3, 3)->ignore
          t->expect(Signal.get(count))->Expect.toBe(3)
          AtomMap.remove(m, 1)->ignore
          t->expect(Signal.get(count))->Expect.toBe(2)
          AtomMap.setValue(m, 2, 20)->ignore // value change only: count unaffected
          t->expect(Signal.get(count))->Expect.toBe(2)
        },
      )

      test(
        "sum tracks the total incrementally",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1.0), (2, 2.0), (3, 3.0)])
          let total = AtomMap.sum(m, (_key, value) => value)
          t->expect(Signal.get(total))->Expect.toBe(6.0)
          AtomMap.setValue(m, 1, 10.0)->ignore
          t->expect(Signal.get(total))->Expect.toBe(15.0)
          AtomMap.remove(m, 2)->ignore
          t->expect(Signal.get(total))->Expect.toBe(13.0)
        },
      )

      test(
        "sum reverts exactly to init when the map becomes empty",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 0.1), (2, 0.2)])
          let total = AtomMap.sum(m, (_key, value) => value)
          Signal.get(total)->ignore
          AtomMap.remove(m, 1)->ignore
          AtomMap.remove(m, 2)->ignore
          t->expect(Signal.get(total))->Expect.toBe(0.0)
        },
      )
    })

    describe("AtomMap: reactivity", () => {
      test(
        "an effect reading a derived map reruns exactly when it changes",
        t => {
          let m = AtomMap.fromArray(~id, [(1, 1)])
          let doubled = AtomMap.mapValues(m, (_key, value) => value * 2)
          let seen = []
          Effect.make(() => Array.push(seen, ComputedMap.toArray(doubled)))->ignore
          t->expect(seen)->Expect.toEqual([[(1, 2)]])
          AtomMap.setValue(m, 2, 2)->ignore
          t->expect(seen)->Expect.toEqual([[(1, 2)], [(1, 2), (2, 4)]])
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

describe("AtomMap (BTree): derived maps", () => {
  test("are built with their source's node size, from scratch and incrementally", t => {
    let m = AtomMap.fromArray(~maxNodeSize=8, ~id, Belt.Array.makeBy(50, i => (i, i)))
    let doubled = AtomMap.mapValues(m, (_key, value) => value * 2)
    let evens = AtomMap.filter(m, (key, _value) => mod(key, 2) === 0)
    let negated = AtomMap.map(m, ~id, (key, value) => (-key, value))
    let nodeSizes = () => [
      ResTrees.BTree.maxNodeSize(ComputedMap.get(doubled)),
      ResTrees.BTree.maxNodeSize(ComputedMap.get(evens)),
      ResTrees.BTree.maxNodeSize(ComputedMap.get(negated)),
    ]
    t->expect(nodeSizes())->Expect.toEqual([8, 8, 8])
    AtomMap.setValue(m, 100, 100)->ignore
    AtomMap.remove(m, 0)->ignore
    t->expect(nodeSizes())->Expect.toEqual([8, 8, 8])
  })
})
