/***
Randomized, model-based tests of the dependency graph: many rounds of a random graph of atoms and
computeds (whose dependencies change with the values they read), put through a random sequence of
writes, batches, reads, and effects being created and disposed.

After every step this checks two things:

- every effect has seen, and every computed that's read returns, exactly what evaluating its
  definition from scratch against the atoms' current values gives;
- the graph's own bookkeeping (`Node.t`'s edges and slots, and which cells are live) is intact --
  the part no test of values alone would catch going wrong until much later.

The sequence is seeded, so a failure reproduces; its message says which round and step.
*/

open Vitest

/**
A small seeded pseudo-random number generator (the Lehmer / "minimal standard" one), so a
randomized test runs the same sequence every time and a failure can be reproduced.
*/
module Random = {
  type t = ref<float>

  let make = (seed: float): t => ref(seed)

  let modFloat = (a: float, m: float): float => a -. m *. Math.floor(a /. m)

  /**
  The next pseudo-random value, in `[1, 2^31 - 2]` for any seed in that range (`0` would be a
  fixed point).
  */
  let next = (state: t): float => {
    state := modFloat(state.contents *. 48271.0, 2147483647.0)
    state.contents
  }

  /** A pseudo-random integer in `[0, bound)`. */
  let nextInt = (state: t, bound: int): int =>
    Float.toInt(modFloat(next(state), Int.toFloat(bound)))
}

// White-box access to the cell behind a signal/effect.
@get external signalCell: Signal.t<'value, 'diff> => Node.t = "cell"
@get external effectCell: EffectBase.t => Node.t = "cell"

let isLive = (cell: Node.t): bool =>
  switch cell.kind {
  | Node.Effect => !cell.disposed
  | Node.Atom | Node.Computed => Array.length(cell.consumers) > 0
  }

/** Throws unless every edge between the given cells is recorded consistently on both sides. */
let checkInvariants = (cells: array<Node.t>): unit =>
  cells->Array.forEach(cell => {
    if Array.length(cell.consumers) !== Array.length(cell.consumerSlots) {
      JsError.throwWithMessage("consumers and consumerSlots differ in length")
    }
    cell.consumers->Array.forEachWithIndex((consumer, slot) => {
      let index = Array.getUnsafe(cell.consumerSlots, slot)
      if !isLive(consumer) {
        JsError.throwWithMessage("a cell that isn't live is linked as a consumer")
      }
      if (
        Array.getUnsafe(consumer.sources, index) !== cell ||
          Array.getUnsafe(consumer.sourceSlots, index) !== slot
      ) {
        JsError.throwWithMessage("a consumer's slot doesn't point back at its source")
      }
    })
    switch cell.kind {
    | Node.Atom => ()
    | Node.Computed | Node.Effect =>
      if isLive(cell) {
        if Array.length(cell.sourceSlots) !== Array.length(cell.sources) {
          JsError.throwWithMessage("sources and sourceSlots differ in length")
        }
        cell.sources->Array.forEachWithIndex((source, index) =>
          if Array.getUnsafe(source.consumers, Array.getUnsafe(cell.sourceSlots, index)) !== cell {
            JsError.throwWithMessage("a source's slot doesn't point back at its consumer")
          }
        )
      } else if cell.sources->Array.some(source => source.consumers->Array.includes(cell)) {
        JsError.throwWithMessage("an idle or disposed cell is still linked into a source")
      }
    }
    if (
      cell.kind === Node.Computed &&
      isLive(cell) &&
      !cell.dirty &&
      cell.sources->Array.some(source => source.dirty)
    ) {
      JsError.throwWithMessage("a clean live computed has a dirty source")
    }
  })

/**
How one computed derives its value: it reads the atom at `selector`, and that value decides how
many of `pool`'s entries it goes on to read and from where it starts -- so its dependencies change
as the atom does. A `pool` entry below `atomCount` is an atom; anything else is an
earlier-defined computed.
*/
type definition = {
  selector: int,
  pool: array<int>,
  /** Whether to read each pool entry twice, to exercise reading the same signal again. */
  readTwice: bool,
}

/** One effect under test, and the value of its `target` computed that it last saw. */
type watcher = {
  effect: EffectBase.t,
  target: int,
  seen: ref<int>,
}

let atomCount = 6
let computedCount = 14
let stepCount = 60

let runRound = (random: Random.t, ~round: int): unit => {
  let values = Array.fromInitializer(~length=atomCount, i => i)
  let atoms = values->Array.map(value => Atom.make(value))
  let definitions = Array.fromInitializer(~length=computedCount, j => {
    selector: Random.nextInt(random, atomCount),
    pool: Array.fromInitializer(~length=1 + Random.nextInt(random, 4), _ =>
      Random.nextInt(random, atomCount + j)
    ),
    readTwice: Random.nextInt(random, 3) === 0,
  })

  // The one definition of what computed `j` is, used both for the real thing (reading signals)
  // and for the model (reading `values`, recursively, with no caching at all).
  let evaluate = (j: int, ~readAtom: int => int, ~readComputed: int => int): int => {
    let {selector, pool, readTwice} = Array.getUnsafe(definitions, j)
    let selected = readAtom(selector)
    let sum = ref(selected)
    for i in 0 to mod(selected, Array.length(pool)) {
      let entry = Array.getUnsafe(pool, mod(i + selected, Array.length(pool)))
      let read = () => entry < atomCount ? readAtom(entry) : readComputed(entry - atomCount)
      sum := sum.contents + read()
      if readTwice {
        sum := sum.contents + read()
      }
    }
    mod(sum.contents, 1000)
  }
  let computeds: array<Signal.t<int, unit>> = []
  for j in 0 to computedCount - 1 {
    Array.push(
      computeds,
      Computed.make(() =>
        evaluate(
          j,
          ~readAtom=i => Atom.get(Array.getUnsafe(atoms, i)),
          ~readComputed=c => Signal.get(Array.getUnsafe(computeds, c)),
        )
      ),
    )
  }
  let rec expected = (j: int): int =>
    evaluate(j, ~readAtom=i => Array.getUnsafe(values, i), ~readComputed=expected)

  let watchers: array<watcher> = []
  // Effects created with the deferring scheduler that are due, until `flush`.
  let queue: array<EffectBase.t> = []
  let flush = () => {
    let due = Array.copy(queue)
    Array.splice(queue, ~start=0, ~remove=Array.length(queue), ~insert=[])
    due->Array.forEach(EffectBase.run)
  }
  let writeRandomAtom = () => {
    let i = Random.nextInt(random, atomCount)
    let value = Random.nextInt(random, 6)
    Array.setUnsafe(values, i, value)
    Atom.set(Array.getUnsafe(atoms, i), value)
  }
  let addWatcher = () => {
    let target = Random.nextInt(random, computedCount)
    let alsoReads =
      Random.nextInt(random, 3) === 0 ? Some(Random.nextInt(random, computedCount)) : None
    let scheduler =
      Random.nextInt(random, 2) === 0 ? EffectBase.run : effect => Array.push(queue, effect)
    let seen = ref(-1)
    let effect = EffectBase.make(~scheduler, () => {
      seen := Signal.get(Array.getUnsafe(computeds, target))
      switch alsoReads {
      | Some(other) => Signal.get(Array.getUnsafe(computeds, other))->ignore
      | None => ()
      }
    })
    Array.push(watchers, {effect, target, seen})
  }
  let removeRandomWatcher = () =>
    if Array.length(watchers) > 0 {
      let index = Random.nextInt(random, Array.length(watchers))
      let {effect} = Array.getUnsafe(watchers, index)
      Array.splice(watchers, ~start=index, ~remove=1, ~insert=[])
      EffectBase.dispose(effect)
      if Array.length(effectCell(effect).sources) > 0 {
        JsError.throwWithMessage("a disposed effect still has sources")
      }
    }
  let check = () => {
    checkInvariants(
      Array.flat([
        atoms->Array.map(atom => signalCell(Atom.toSignal(atom))),
        computeds->Array.map(signalCell),
        watchers->Array.map(watcher => effectCell(watcher.effect)),
      ]),
    )

    // With nothing waiting on `flush`, every effect has caught up -- deferred or not.
    if Array.length(queue) === 0 {
      watchers->Array.forEach(({target, seen}) =>
        if seen.contents !== expected(target) {
          JsError.throwWithMessage(
            `an effect on computed ${Int.toString(target)} last saw ${Int.toString(
                seen.contents,
              )}, but it's now ${Int.toString(expected(target))}`,
          )
        }
      )
    }
  }
  let readAndCompare = (j: int) => {
    let actual = Signal.get(Array.getUnsafe(computeds, j))
    if actual !== expected(j) {
      JsError.throwWithMessage(
        `computed ${Int.toString(j)} is ${Int.toString(actual)}, expected ${Int.toString(
            expected(j),
          )}`,
      )
    }
  }

  let step = ref(0)
  try {
    while step.contents < stepCount {
      step := step.contents + 1
      switch Random.nextInt(random, 10) {
      | 0 | 1 | 2 | 3 => writeRandomAtom()
      | 4 =>
        Batch.run(() => {
          writeRandomAtom()
          writeRandomAtom()
          writeRandomAtom()
        })
      | 5 | 6 => addWatcher()
      | 7 => removeRandomWatcher()
      | 8 => flush()
      | _ => readAndCompare(Random.nextInt(random, computedCount))
      }
      check()
    }

    flush()
    check()
    for j in 0 to computedCount - 1 {
      readAndCompare(j)
    }
    // With every effect gone, nothing is live, so no signal should be holding on to a consumer.
    while Array.length(watchers) > 0 {
      removeRandomWatcher()
    }
    check()
    Array.concat(
      atoms->Array.map(atom => signalCell(Atom.toSignal(atom))),
      computeds->Array.map(signalCell),
    )->Array.forEach(cell =>
      if Array.length(cell.consumers) > 0 {
        JsError.throwWithMessage("a signal still has consumers after every effect was disposed")
      }
    )
  } catch {
  | JsExn(error) =>
    JsError.throwWithMessage(
      `round ${Int.toString(round)}, step ${Int.toString(step.contents)}: ${error
        ->JsExn.message
        ->Option.getOr("unknown error")}`,
    )
  }
}

describe("the dependency graph, under random operations", () => {
  test("values match a from-scratch evaluation, and the graph's bookkeeping stays intact", t => {
    let random = Random.make(20261011.0)
    let rounds = 300
    for round in 1 to rounds {
      runRound(random, ~round)
    }
    t->expect(rounds)->Expect.toBe(300)
  })
})
