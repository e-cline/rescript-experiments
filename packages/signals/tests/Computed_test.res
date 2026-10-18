open Vitest

describe("Computed.make: basic derivation", () => {
  test("derives its value from an atom, lazily", t => {
    let calls = ref(0)
    let a = Atom.make(1)
    let doubled = Computed.make(
      () => {
        calls := calls.contents + 1
        Atom.get(a) * 2
      },
    )
    t->expect(calls.contents)->Expect.toBe(0) // not yet read
    t->expect(Signal.get(doubled))->Expect.toBe(2)
    t->expect(calls.contents)->Expect.toBe(1)
    t->expect(Signal.get(doubled))->Expect.toBe(2)
    t->expect(calls.contents)->Expect.toBe(1) // cached, no recompute
  })

  test("recomputes only after a dependency actually changes", t => {
    let calls = ref(0)
    let a = Atom.make(1)
    let doubled = Computed.make(
      () => {
        calls := calls.contents + 1
        Atom.get(a) * 2
      },
    )
    Signal.get(doubled)->ignore
    Atom.set(a, 1) // no-op set, equal value
    t->expect(Signal.get(doubled))->Expect.toBe(2)
    t->expect(calls.contents)->Expect.toBe(1)
    Atom.set(a, 5)
    t->expect(Signal.get(doubled))->Expect.toBe(10)
    t->expect(calls.contents)->Expect.toBe(2)
  })

  test("a diamond dependency graph recomputes the shared descendant exactly once per change", t => {
    let calls = ref(0)
    let a = Atom.make(1)
    let left = Computed.make(() => Atom.get(a) + 1)
    let right = Computed.make(() => Atom.get(a) + 2)
    let combined = Computed.make(
      () => {
        calls := calls.contents + 1
        Signal.get(left) + Signal.get(right)
      },
    )
    t->expect(Signal.get(combined))->Expect.toBe(5) // (1+1) + (1+2)
    t->expect(calls.contents)->Expect.toBe(1)
    Atom.set(a, 10)
    t->expect(Signal.get(combined))->Expect.toBe(23) // (10+1) + (10+2)
    t->expect(calls.contents)->Expect.toBe(2)
  })

  test("dependencies are pruned when a branch stops being read", t => {
    let switch_ = Atom.make(true)
    let onTrue = Atom.make(1)
    let onFalse = Atom.make(2)
    let calls = ref(0)
    let result = Computed.make(
      () => {
        calls := calls.contents + 1
        Atom.get(switch_) ? Atom.get(onTrue) : Atom.get(onFalse)
      },
    )
    t->expect(Signal.get(result))->Expect.toBe(1)
    Atom.set(switch_, false)
    t->expect(Signal.get(result))->Expect.toBe(2)
    t->expect(calls.contents)->Expect.toBe(2)
    // onTrue is no longer a dependency; changing it must not trigger a recompute.
    Atom.set(onTrue, 100)
    Signal.get(result)->ignore
    t->expect(calls.contents)->Expect.toBe(2)
  })

  test("detects a self-referential cycle", t => {
    let cyclic: ref<option<Signal.t<int, unit>>> = ref(None)
    let signal = Computed.make(
      () => {
        switch cyclic.contents {
        | Some(s) => Signal.get(s)
        | None => 0
        }
      },
    )
    cyclic := Some(signal)
    t->expect(() => Signal.get(signal))->Expect.toThrow
  })
})

describe("Computed.makeIncremental: diffing", () => {
  test("the first computation records no diff (nothing to diff against)", t => {
    let a = Atom.makeIncremental(~historyLength=4, ~computeDiff=(_, next, _, _) => Some(next), 1)
    let doubled = Computed.makeIncremental(
      ~historyLength=4,
      (previous, _lastComputedEpoch) =>
        switch previous {
        | None => Computed.Value(Atom.get(a) * 2)
        | Some(_) => Computed.Value(Atom.get(a) * 2)
        },
    )
    // There's no well-defined epoch "before" a computed's first value existed
    // (unlike an atom, which starts at a real value from epoch 0): asking for
    // diffs since any epoch predating the first computation always answers
    // `Reset`, since the history buffer holds nothing to replay yet.
    t->expect(Signal.get(doubled))->Expect.toBe(2)
    t->expect(Signal.getDiffSince(doubled, 0))->Expect.toEqual(Signal.Reset)
    // But asking again right after that first computation, from the epoch it
    // just settled at, correctly answers "nothing changed since."
    let epoch1 = Signal.lastChangedEpoch(doubled)
    t->expect(Signal.getDiffSince(doubled, epoch1))->Expect.toEqual(Signal.Diffs([]))
  })

  test("ValueWithDiff records the explicit diff instead of consulting computeDiff", t => {
    let a = Atom.make(0)
    let calls = ref(0)
    let tracked = Computed.makeIncremental(
      ~historyLength=4,
      ~computeDiff=(_, _, _, _) => {
        calls := calls.contents + 1
        Some("from-computeDiff")
      },
      (previous, _) =>
        switch previous {
        | None => Computed.Value(Atom.get(a))
        | Some(prev) => Computed.ValueWithDiff(Atom.get(a), `${Int.toString(prev)}->explicit`)
        },
    )
    Signal.get(tracked)->ignore
    let epoch0 = Signal.lastChangedEpoch(tracked)
    Atom.set(a, 1)
    Signal.get(tracked)->ignore
    t->expect(Signal.getDiffSince(tracked, epoch0))->Expect.toEqual(Signal.Diffs(["0->explicit"]))
    t->expect(calls.contents)->Expect.toBe(0)
  })

  test("a recompute to an equal value leaves no gap in the recorded history", t => {
    let a = Atom.make(1)
    let tens = Computed.makeIncremental(
      ~historyLength=4,
      ~computeDiff=(previous, next, _, _) => Some((previous, next)),
      (_, _) => Computed.Value(Atom.get(a) / 10),
    )
    Signal.get(tens)->ignore
    Atom.set(a, 10)
    Signal.get(tens)->ignore
    let inSyncAt = Signal.lastChangedEpoch(tens) // where a consumer last caught up
    Atom.set(a, 11)
    Signal.get(tens)->ignore // recomputes, but to an equal value: nothing recorded
    t->expect(Signal.getDiffSince(tens, inSyncAt))->Expect.toEqual(Signal.Diffs([]))
    Atom.set(a, 20)
    Signal.get(tens)->ignore
    t->expect(Signal.getDiffSince(tens, inSyncAt))->Expect.toEqual(Signal.Diffs([(1, 2)]))
  })

  test("a computed that stops changing stops propagating to its own consumers", t => {
    let a = Atom.make(1)
    let parityCalls = ref(0)
    let downstreamCalls = ref(0)
    let parity = Computed.make(
      () => {
        parityCalls := parityCalls.contents + 1
        mod(Atom.get(a), 2)
      },
    )
    let downstream = Computed.make(
      () => {
        downstreamCalls := downstreamCalls.contents + 1
        Signal.get(parity) + 1
      },
    )
    t->expect(Signal.get(downstream))->Expect.toBe(2)
    Atom.set(a, 3) // still odd: parity unchanged
    t->expect(Signal.get(downstream))->Expect.toBe(2)
    t->expect(parityCalls.contents)->Expect.toBe(2)
    t->expect(downstreamCalls.contents)->Expect.toBe(1)
  })
})

// White-box: how many consumers the atom's cell currently holds on to.
let consumerCount: Atom.t<'value, 'diff> => int = %raw(`atom => atom.cell.consumers.length`)

module Effect = EffectBase.Make(Scheduler.Sync)

describe("Computed: dependency tracking", () => {
  test("reading the same signal repeatedly registers it once", t => {
    let a = Atom.make(1)
    let calls = ref(0)
    let tripled = Computed.make(
      () => {
        calls := calls.contents + 1
        Atom.get(a) + Atom.get(a) + Atom.get(a)
      },
    )
    let effect = Effect.make(() => Signal.get(tripled)->ignore)
    t->expect(consumerCount(a))->Expect.toBe(1)
    Atom.set(a, 2)
    t->expect(Signal.get(tripled))->Expect.toBe(6)
    t->expect(calls.contents)->Expect.toBe(2)
    t->expect(consumerCount(a))->Expect.toBe(1)
    Effect.dispose(effect)
  })

  test("dependencies can be dropped, added and reordered from one run to the next", t => {
    let order = Atom.make([0, 1, 2, 3])
    let atoms = [Atom.make(1), Atom.make(10), Atom.make(100), Atom.make(1000)]
    let sum = Computed.make(
      () => Atom.get(order)->Array.reduce(0, (acc, i) => acc + Atom.get(Array.getUnsafe(atoms, i))),
    )
    let seen = []
    let effect = Effect.make(() => Array.push(seen, Signal.get(sum)))
    let counts = () => atoms->Array.map(consumerCount)
    t->expect(counts())->Expect.toEqual([1, 1, 1, 1])
    Atom.set(order, [3, 1]) // drops two, reorders the rest
    t->expect(counts())->Expect.toEqual([0, 1, 0, 1])
    Atom.set(Array.getUnsafe(atoms, 0), 2) // no longer read
    Atom.set(Array.getUnsafe(atoms, 3), 2000)
    Atom.set(order, [0, 3, 2, 1, 0]) // adds two back, in the middle and at both ends
    t->expect(counts())->Expect.toEqual([1, 1, 1, 1])
    Atom.set(Array.getUnsafe(atoms, 2), 200)
    Atom.set(order, [])
    t->expect(counts())->Expect.toEqual([0, 0, 0, 0])
    t->expect(seen)->Expect.toEqual([1111, 1010, 2010, 2114, 2214, 0])
    Effect.dispose(effect)
  })
})

describe("Computed: idle until something consumes it", () => {
  test(
    "a computed nothing consumes isn't held on to by its sources, but still stays current",
    t => {
      let a = Atom.make(1)
      let calls = ref(0)
      let doubled = Computed.make(
        () => {
          calls := calls.contents + 1
          Atom.get(a) * 2
        },
      )
      t->expect(Signal.get(doubled))->Expect.toBe(2)
      t->expect(consumerCount(a))->Expect.toBe(0)
      t->expect(Signal.get(doubled))->Expect.toBe(2)
      t->expect(calls.contents)->Expect.toBe(1)
      Atom.set(a, 2)
      t->expect(Signal.get(doubled))->Expect.toBe(4)
      t->expect(calls.contents)->Expect.toBe(2)
      // An unrelated write means it has to check its sources again, but not recompute.
      Atom.set(Atom.make(0), 1)
      t->expect(Signal.get(doubled))->Expect.toBe(4)
      t->expect(calls.contents)->Expect.toBe(2)
    },
  )

  test("a chain goes live when an effect reads its end, and idle again once that's disposed", t => {
    let a = Atom.make(1)
    let plusOne = Computed.make(() => Atom.get(a) + 1)
    let calls = ref(0)
    let doubled = Computed.make(
      () => {
        calls := calls.contents + 1
        Signal.get(plusOne) * 2
      },
    )
    t->expect(Signal.get(doubled))->Expect.toBe(4) // computed while idle
    let seen = []
    let effect = Effect.make(() => Array.push(seen, Signal.get(doubled)))
    t->expect(consumerCount(a))->Expect.toBe(1)
    t->expect(calls.contents)->Expect.toBe(1) // going live doesn't recompute
    Atom.set(a, 2)
    t->expect(seen)->Expect.toEqual([4, 6])
    Effect.dispose(effect)
    t->expect(consumerCount(a))->Expect.toBe(0)
    Atom.set(a, 3)
    t->expect(Signal.get(doubled))->Expect.toBe(8)
    t->expect(calls.contents)->Expect.toBe(3)
  })

  test("a computed shared by two effects stays live until both are disposed", t => {
    let a = Atom.make(1)
    let doubled = Computed.make(() => Atom.get(a) * 2)
    let first = Effect.make(() => Signal.get(doubled)->ignore)
    let second = Effect.make(() => Signal.get(doubled)->ignore)
    Effect.dispose(first)
    t->expect(consumerCount(a))->Expect.toBe(1)
    Effect.dispose(second)
    t->expect(consumerCount(a))->Expect.toBe(0)
  })

  test("a change made while idle is seen by an effect that starts reading afterwards", t => {
    let a = Atom.make(1)
    let doubled = Computed.make(() => Atom.get(a) * 2)
    let first = Effect.make(() => Signal.get(doubled)->ignore)
    Batch.run(
      () => {
        Atom.set(a, 2) // marks `doubled` dirty...
        Effect.dispose(first) // ...and it goes idle before anything reads it again
      },
    )
    let seen = []
    Effect.make(() => Array.push(seen, Signal.get(doubled)))->ignore
    Atom.set(a, 3)
    t->expect(seen)->Expect.toEqual([4, 6])
  })
})
