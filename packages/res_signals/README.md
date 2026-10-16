# @e-cline/res_signals

A ReScript-authored reactive signals library -- `Atom`, `Computed`, `EffectBase`, `Batch`,
`Untracked` -- with a small, dependency-free core: dependency tracking, lazy recomputation, and
diff-driven history. This package has no dependencies of its own; see
[`@e-cline/res_signal_maps`](../res_signal_maps) for `AtomMap`/`ComputedMap`, a sorted,
signal-backed map built on top of it (and on [`@e-cline/res_trees`](../res_trees)) whose derived
views (`mapValues`, `filterMap`, `map`, `fold`, ...) update incrementally from a diff instead of
recomputing from scratch on every change.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/res_signals rescript @rescript/runtime
```

Add `"@e-cline/res_signals"` to the `dependencies` in your `rescript.json`. The modules are under
the `ResSignals` namespace (`ResSignals.Atom.make`), and your project's `rescript build` compiles
them along with your own code.

## Core reactive primitives

- **`Atom.t<'value, 'diff>`** -- a mutable signal, created with `Atom.make` and updated with
  `Atom.set`/`Atom.update`. (`'diff` is `unit` unless the atom was created with
  `Atom.makeIncremental`: see "Diffing" below.)
- **`Computed`** -- `Computed.make(() => ...)` derives a value from other signals, recomputing
  lazily (only when read) and only as much as it needs to: see "Reactive graph" below.
- **`EffectBase`** -- an effect runs immediately, then reruns after a signal it read last time
  changes, until disposed. _When_ it reruns is up to a scheduler the application supplies: see
  "Effects and schedulers" below.
- **`Batch.run(() => ...)`** -- groups writes so effects they trigger are notified once, after every
  write in the batch has landed, instead of once per write.
- **`Untracked.run(() => ...)`** -- reads signals without establishing a dependency.
- **`Signal.t<'value, 'diff>`** -- the shared read-only view of both: what `Computed.make` returns,
  and what `Atom.toSignal` (a free cast) turns an atom into. Read with
  `Signal.get`/`peek`/`lastChangedEpoch`/`getDiffSince`.

```rescript
module Effect = EffectBase.Make(Scheduler.Sync)

let count = Atom.make(0)
let doubled = Computed.make(() => Atom.get(count) * 2)
Effect.make(() => Console.log(Signal.get(doubled)))->ignore // logs 0
Atom.set(count, 5) // logs 10
```

### Effects and schedulers

There is no ready-to-use `Effect` module: the graph only works out _that_ an effect is due, and
leaves _when_ it reruns to a scheduler. An application builds its own `Effect` once, from the
scheduler it wants:

```rescript
module Effect = ResSignals.EffectBase.Make(ResSignals.Scheduler.Microtask)
```

- **`Scheduler.Sync`** -- reruns as soon as the write returns, or when the outermost `Batch.run`
  exits.
- **`Scheduler.Microtask`** -- reruns in a microtask, so any number of writes in the same
  synchronous stretch of code rerun an effect once. Every effect due shares one microtask.
- **Your own** -- a scheduler is a function `EffectBase.t => unit`, called once each time an effect
  goes from idle to due (after the write, or outermost batch, that caused it has fully landed). It
  must arrange for `EffectBase.run` to be called on that effect, whenever suits: an animation frame,
  a priority queue, a queue a test flushes by hand, ...

  ```rescript
  module Effect = EffectBase.Make({
    let schedule = effect => requestAnimationFrame(_ => EffectBase.run(effect))->ignore
  })
  ```

  Code that can't commit to one scheduler (a library, say) can take one as a value instead:
  `EffectBase.make(~scheduler, () => ...)`.

`EffectBase.run` only reruns an effect if a signal it read has actually changed, so an effect behind
a `Computed` that recomputed to an equal value doesn't rerun. The first run always happens
synchronously, on creation.

**Cleanup.** `makeWithCleanup` is for an effect that sets something up which has to be undone: the
function it returns, if any, is called just before the effect next reruns, or when it's disposed.

```rescript
Effect.makeWithCleanup(() => {
  let timer = setInterval(tick, Atom.get(period))
  Some(() => clearInterval(timer))
})
```

**Ownership.** An effect created while another effect is running belongs to that run: it's disposed
when the outer effect reruns or is disposed, so an effect that sets up further effects doesn't
accumulate a new set of them each time.

**Errors.** An effect that throws isn't disposed by it: it stays subscribed to what it read, and
reruns on the next change. Where the exception goes depends on the scheduler:

- With `Scheduler.Sync`, the other effects due still run, and then the first exception thrown
  propagates out of the `Atom.set`/`Batch.run` that triggered them.
- With `Scheduler.Microtask`, the other effects due still run too, and each exception is then
  reported as an uncaught one (there's no caller left to throw it to).
- An effect that throws on its very first run is disposed, and `make` throws.

Effects that keep triggering each other without ever settling (most simply, one that writes a signal
it reads, to a new value every time) don't hang: after 100 rounds, `Scheduler.Sync` throws from the
write that started it, and `Scheduler.Microtask` stops and reports an uncaught error.

### Reactive graph: dirty-flag propagation with an epoch-based short-circuit

`internal/Node.res` is the whole dependency graph: a write marks every transitively reachable live
`Computed`/effect "dirty" (cheap, no recomputation) and queues affected effects to be handed to
their scheduler; nothing actually recomputes until something reads it. A dirty `Computed`'s
`Node.ensureFresh` doesn't recompute unconditionally, though -- it first resolves each of its own
sources (recursively), then checks whether any of them has a `lastChangedEpoch` _newer_ than the
epoch this computed last computed at. Only then does it re-run its compute function. This means a
diamond-shaped dependency graph, or a computed whose own recompute happens to produce an equal
value, never causes redundant downstream recomputation -- see `internal/Node.resi`'s documentation
of `markDirty`/`ensureFresh` for the full reasoning, and `Computed_test.res` for tests exercising it
directly (a diamond graph recomputing its shared descendant exactly once per change; a computed
whose value doesn't change not triggering its own consumers).

A computed is only _live_ -- registered with the signals it reads, and so reachable by that marking
-- while an effect (directly, or through other computeds) is consuming it. One that nothing consumes
is _idle_: its sources hold no reference to it, so there's nothing to dispose, and dropping it is
enough for it to be garbage collected. Reading an idle computed still gives a current value; it just
has to check its sources' epochs itself, having not been told whether they changed.

Tracking a read, and adding or removing a dependency, each take constant time, however many
dependencies or consumers are involved; a computation that reads the same signals in the same order
as last time allocates nothing for it. The one cost that still grows with the graph's _depth_ is the
call stack: reading the end of a chain of computeds recurses once per link that has to be checked or
recomputed.

Scheduling is deliberately **not** part of the graph: `internal/Node.res`'s `settle` only tells each
due effect's scheduler about it, once the write (or outermost `Batch.run`) has landed.

### Diffing

An atom or computed created with `Atom.makeIncremental`/ `Computed.makeIncremental` can retain a
bounded history of diffs (`~historyLength`), and `Signal.getDiffSince(signal, epoch)` answers either
every diff since then or `Signal.Reset` when it can't (no history was kept, the epoch is older than
the buffer, or a change along the way couldn't be expressed as a diff). This is what lets
[`@e-cline/res_signal_maps`](../res_signal_maps)'s `AtomMap`/`ComputedMap` derived-map operations
update incrementally instead of diffing (or rebuilding) the whole structure on every read.

## Tests and benchmarks

Besides the per-module tests, `tests/Fuzz_test.res` is a randomized, model-based test of the graph:
random graphs whose dependencies change with the values they read, put through random writes,
batches, reads, and effects being created and disposed. After every step it compares each value
against a from-scratch evaluation and checks the graph's internal bookkeeping. It's seeded, so it
runs the same sequence every time, as part of the ordinary `test` task.

The benchmarks in [`benchmarks/`](benchmarks) (a separate, unpublished package) measure how the
graph's costs scale -- many atoms under one computed, many effects or computeds on one atom, and a
long chain of computeds, both live and idle -- each at two sizes, so a cost that grows faster than
the graph does stands out:

```bash
pnpm --filter @e-cline/res_signals_benchmarks exec vp run bench
```
