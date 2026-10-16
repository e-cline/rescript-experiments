open Vitest

describe("Atom: basic get/set", () => {
  test("get returns the initial value", t => {
    let a = Atom.make(1)
    t->expect(Atom.get(a))->Expect.toBe(1)
  })

  test("set updates the value", t => {
    let a = Atom.make(1)
    Atom.set(a, 2)
    t->expect(Atom.get(a))->Expect.toBe(2)
  })

  test("set with an equal value is a no-op", t => {
    let a = Atom.make(1)
    let epochBefore = Atom.lastChangedEpoch(a)
    Atom.set(a, 1)
    t->expect(Atom.lastChangedEpoch(a))->Expect.toBe(epochBefore)
  })

  test("update derives the new value from the current one", t => {
    let a = Atom.make(1)
    Atom.update(a, n => n + 1)
    t->expect(Atom.get(a))->Expect.toBe(2)
  })

  test("a custom equal function controls no-op detection", t => {
    let a = Atom.make(~equal=(x, y) => mod(x, 10) === mod(y, 10), 1)
    Atom.set(a, 11) // 11 mod 10 = 1 mod 10, so no-op
    t->expect(Atom.get(a))->Expect.toBe(1)
    Atom.set(a, 2)
    t->expect(Atom.get(a))->Expect.toBe(2)
  })
})

describe("Atom: diffing", () => {
  test("with no historyLength, getDiffSince always answers Reset once something changed", t => {
    let a = Atom.make(1)
    let epoch0 = Atom.lastChangedEpoch(a)
    Atom.set(a, 2)
    t->expect(Atom.getDiffSince(a, epoch0))->Expect.toEqual(Signal.Reset)
  })

  test("getDiffSince at or after the current epoch answers an empty Diffs", t => {
    let a = Atom.makeIncremental(~historyLength=4, 1)
    let epoch = Atom.lastChangedEpoch(a)
    t->expect(Atom.getDiffSince(a, epoch))->Expect.toEqual(Signal.Diffs([]))
  })

  test("explicit diffs are recorded and replayed in order via getDiffSince", t => {
    let a = Atom.makeIncremental(~historyLength=4, 0)
    let epoch0 = Atom.lastChangedEpoch(a)
    Atom.set(a, ~diff="to-1", 1)
    Atom.set(a, ~diff="to-2", 2)
    t->expect(Atom.getDiffSince(a, epoch0))->Expect.toEqual(Signal.Diffs(["to-1", "to-2"]))
  })

  test("computeDiff is used when set/update don't supply a diff explicitly", t => {
    let a = Atom.makeIncremental(
      ~historyLength=4,
      ~computeDiff=(prev, next, _, _) => Some(next - prev),
      0,
    )
    let epoch0 = Atom.lastChangedEpoch(a)
    Atom.set(a, 5)
    Atom.set(a, 8)
    t->expect(Atom.getDiffSince(a, epoch0))->Expect.toEqual(Signal.Diffs([5, 3]))
  })

  test("an epoch older than the buffer's capacity answers Reset", t => {
    let a = Atom.makeIncremental(~historyLength=2, 0)
    let epoch0 = Atom.lastChangedEpoch(a)
    Atom.set(a, ~diff="a", 1)
    Atom.set(a, ~diff="b", 2)
    Atom.set(a, ~diff="c", 3)
    t->expect(Atom.getDiffSince(a, epoch0))->Expect.toEqual(Signal.Reset)
  })

  test("a None diff from computeDiff clears history (falls back to Reset)", t => {
    let shouldReset = ref(false)
    let a = Atom.makeIncremental(
      ~historyLength=4,
      ~computeDiff=(_, _, _, _) => shouldReset.contents ? None : Some("ok"),
      0,
    )
    let epoch0 = Atom.lastChangedEpoch(a)
    Atom.set(a, 1)
    shouldReset := true
    Atom.set(a, 2)
    t->expect(Atom.getDiffSince(a, epoch0))->Expect.toEqual(Signal.Reset)
  })
})

describe("Atom: writes while a computed is evaluating", () => {
  test("writing an atom from inside a computed's compute function throws", t => {
    let source = Atom.make(1)
    let sideEffectTarget = Atom.make(0)
    let derived = Computed.make(
      () => {
        Atom.set(sideEffectTarget, Atom.get(source))
        Atom.get(source)
      },
    )
    t->expect(() => Signal.get(derived))->Expect.toThrow
  })
})

// At the top level of a module, where a diff type left undetermined wouldn't compile.
let topLevel = Atom.make(1)

describe("Atom.toSignal", () => {
  test("is the atom itself, however many times it's called", t => {
    t->expect(Atom.toSignal(topLevel) === Atom.toSignal(topLevel))->Expect.toBe(true)
    t->expect(Signal.get(Atom.toSignal(topLevel)))->Expect.toBe(1)
  })

  test("exposes the same value and epoch as the atom", t => {
    let a = Atom.makeIncremental(~historyLength=4, ~computeDiff=(_, next, _, _) => Some(next), 1)
    let signal = Atom.toSignal(a)
    t->expect(Signal.get(signal))->Expect.toBe(1)
    let epoch0 = Signal.lastChangedEpoch(signal)
    Atom.set(a, 2)
    t->expect(Signal.get(signal))->Expect.toBe(2)
    t->expect(Signal.lastChangedEpoch(signal))->Expect.not->Expect.toBe(epoch0)
    t->expect(Signal.getDiffSince(signal, epoch0))->Expect.toEqual(Signal.Diffs([2]))
  })
})
