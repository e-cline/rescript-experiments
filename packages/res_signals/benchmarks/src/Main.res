/***
Benchmarks of the dependency graph, chosen to show how its costs scale: each group runs at two
sizes, so anything that isn't (roughly) proportional to the size stands out.

Every benchmark passes what it reads to `Mitata.doNotOptimize`, as does every effect and computed
that reads only to establish a dependency. This file is bundled together with the code it measures
(see ../vite.config.ts), so without that both Terser and the JIT could see that a result is unused
and delete the work that produced it.

Every benchmark that measures an existing graph builds its own, when it runs (see
`Mitata.benchWithSetup`), and disposes of any effects on it once measured, so no graph outlives
its benchmark.

Benchmark names include the graph's size, since the filter argument (see `Runner.main`) matches on
a benchmark's own name, not its group's.
*/

open ResBenchmarking
module Atom = ResSignals.Atom
module Computed = ResSignals.Computed
module Signal = ResSignals.Signal
module Effect = ResSignals.EffectBase.Make(ResSignals.Scheduler.Sync)

let makeAtoms = (count: int): array<Atom.t<int, unit>> =>
  Array.fromInitializer(~length=count, i => Atom.make(i))

let sumOf = (atoms: array<Atom.t<int, unit>>): Signal.t<int, unit> =>
  Computed.make(() => atoms->Array.reduce(0, (sum, atom) => sum + Atom.get(atom)))

/** A computed that adds one to the source, then another that adds one to that, and so on. */
let makeChain = (source: Signal.t<int, unit>, ~length: int): Signal.t<int, unit> => {
  let last = ref(source)
  for _ in 1 to length {
    let previous = last.contents
    last := Computed.make(() => Signal.get(previous) + 1)
  }
  last.contents
}

let increment = (atom: Atom.t<int, unit>): unit => Atom.update(atom, n => n + 1)

/** An effect that does nothing but depend on `signal`. */
let watch = (signal: Signal.t<int, unit>): Effect.t =>
  Effect.make(() => Mitata.doNotOptimize(Signal.get(signal)))

let benchGraphOfSize = (size: int) => {
  let n = Int.toString(size)

  Mitata.group(`one computed reading ${n} atoms`, () => {
    Mitata.benchWithSetup(`write one of ${n} atoms, then read the computed (idle)`, () => {
      let atoms = makeAtoms(size)
      let sum = sumOf(atoms)
      Mitata.doNotOptimize(Signal.get(sum))
      {
        measure: () => {
          increment(Array.getUnsafe(atoms, 0))
          Mitata.doNotOptimize(Signal.get(sum))
        },
      }
    })->ignore

    Mitata.benchWithSetup(
      `write one of ${n} atoms, rerunning an effect on the computed (live)`,
      () => {
        let atoms = makeAtoms(size)
        let effect = watch(sumOf(atoms))
        {
          measure: () => increment(Array.getUnsafe(atoms, 0)),
          teardown: () => Effect.dispose(effect),
        }
      },
    )->ignore
  })

  Mitata.group(`${n} effects on one atom`, () => {
    Mitata.bench(`create ${n} effects, then dispose them all`, () => {
      let atom = Atom.toSignal(Atom.make(0))
      let effects = Array.fromInitializer(~length=size, _ => watch(atom))
      effects->Array.forEach(Effect.dispose)
    })->ignore

    Mitata.benchWithSetup(`one write, rerunning ${n} effects`, () => {
      let atom = Atom.make(0)
      let effects = Array.fromInitializer(~length=size, _ => watch(Atom.toSignal(atom)))
      {measure: () => increment(atom), teardown: () => effects->Array.forEach(Effect.dispose)}
    })->ignore
  })

  Mitata.group(`${n} computeds on one atom`, () => {
    Mitata.bench(`create and read ${n} computeds, then drop them (idle)`, () => {
      let atom = Atom.make(0)
      for i in 1 to size {
        Mitata.doNotOptimize(Signal.get(Computed.make(() => Atom.get(atom) + i)))
      }
    })->ignore

    Mitata.benchWithSetup(`one write, recomputing ${n} computeds for an effect (live)`, () => {
      let atom = Atom.make(0)
      let computeds = Array.fromInitializer(
        ~length=size,
        i => Computed.make(() => Atom.get(atom) + i),
      )
      let effect = Effect.make(
        () => computeds->Array.forEach(computed => Mitata.doNotOptimize(Signal.get(computed))),
      )
      {measure: () => increment(atom), teardown: () => Effect.dispose(effect)}
    })->ignore
  })
}

/** Shorter than the sizes above: reading the end of a chain recurses once per link. */
let benchChain = (length: int) => {
  let n = Int.toString(length)
  let named = (name: string) => `chain of ${n}: ${name}`

  // A chain from a new atom, read once so that the benchmark starts from an up-to-date end.
  let idleChain = () => {
    let atom = Atom.make(0)
    let end = makeChain(Atom.toSignal(atom), ~length)
    Mitata.doNotOptimize(Signal.get(end))
    (atom, end)
  }

  Mitata.group(`a chain of ${n} computeds`, () => {
    Mitata.benchWithSetup(named("write the atom, rerunning an effect on the end (live)"), () => {
      let atom = Atom.make(0)
      let effect = watch(makeChain(Atom.toSignal(atom), ~length))
      {measure: () => increment(atom), teardown: () => Effect.dispose(effect)}
    })->ignore

    Mitata.benchWithSetup(named("write the atom, then read the end (idle)"), () => {
      let (atom, end) = idleChain()
      {
        measure: () => {
          increment(atom)
          Mitata.doNotOptimize(Signal.get(end))
        },
      }
    })->ignore

    // What being idle costs: nothing told the chain that the write didn't concern it, so it has
    // to check every link.
    Mitata.benchWithSetup(named("write an unrelated atom, then read the end (idle)"), () => {
      let (_, end) = idleChain()
      let unrelated = Atom.make(0)
      {
        measure: () => {
          increment(unrelated)
          Mitata.doNotOptimize(Signal.get(end))
        },
      }
    })->ignore

    Mitata.benchWithSetup(named("read the end again, nothing written (idle)"), () => {
      let (_, end) = idleChain()
      {measure: () => Mitata.doNotOptimize(Signal.get(end))}
    })->ignore
  })
}

[1_000, 16_000]->Array.forEach(benchGraphOfSize)
benchChain(1_000)

(await Runner.main())->ignore
