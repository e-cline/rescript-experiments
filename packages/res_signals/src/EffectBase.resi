/***
A reaction to signal changes: runs immediately, then reruns whenever a signal it read last time
changes, until disposed -- with *when* it reruns left to a scheduler the application supplies.

This package deliberately has no `Effect` module of its own. An application picks a scheduler
(one of the ready-made ones in `Scheduler`, or its own) and builds its `Effect` from it, once:

```rescript
module Effect = ResSignals.EffectBase.Make(ResSignals.Scheduler.Microtask)

Effect.make(() => Console.log(Atom.get(count)))->ignore
```

## Ownership

An effect created while another effect's function is running belongs to that run: it's disposed
when the outer effect next reruns (which will create it afresh, if it still wants it) or is itself
disposed. So an effect that sets up further effects doesn't accumulate a new set of them every time
it reruns.

## Errors

An effect whose function throws isn't disposed by that: it stays subscribed to whatever it read
before throwing, and reruns when one of those changes. Where the exception surfaces is up to the
scheduler, since that's what called `run` -- see `Scheduler` for the ready-made ones. The one
exception is the first run, which happens inside `make`: if that throws, the effect is disposed
(there'd be no handle to do so with later) and `make` throws.
*/

/** An effect. */
type t

/**
Decides when a due effect reruns. Called with an effect once each time it goes from idle to due
(i.e. a signal it read last time *might* have changed), after the write that made it due -- or the
outermost `Batch.run` around that write -- has fully landed. It must arrange for `run` to be called
on that effect, either on the spot or later (a microtask, an animation frame, a queue of its own,
...); until it is, further changes don't call the scheduler for that effect again.

Anything a scheduler throws -- including what `run` throws, if it calls that on the spot --
surfaces from the `Atom.set`/`Batch.run` that made the effect due, but only once every other effect
that write made due has been handed to its own scheduler; if several throw, the first is the one
rethrown.
*/
type scheduler = t => unit

/**
Creates an effect that runs the function now, synchronously, and again -- whenever the scheduler
gets round to it -- after a signal it read during its previous run changes. Dependencies are
re-collected on every run, so a signal it stops reading stops triggering it.
*/
let make: (~scheduler: scheduler, unit => unit) => t

/**
Like `make`, for a function that sets something up which has to be undone: if it returns
`Some(cleanup)`, `cleanup` is called once, just before the function next reruns, or when the effect
is disposed -- whichever comes first.

```rescript
EffectBase.makeWithCleanup(~scheduler, () => {
  let timer = setInterval(tick, Atom.get(period))
  Some(() => clearInterval(timer))
})
```

Signals a cleanup function reads aren't tracked, and effects it creates aren't owned by anything.
If one throws, the rerun or disposal it was part of is abandoned with that exception (after
anything else due for cleanup at the same time has still been cleaned up); a rerun abandoned this
way is attempted again the next time a signal the effect read changes.
*/
let makeWithCleanup: (~scheduler: scheduler, unit => option<unit => unit>) => t

/**
Reruns the effect if it's due -- what a scheduler calls once it's time. A no-op if the effect isn't
due or has been disposed, so calling it late, or more than once, is harmless. Also skips the
function (but still leaves the effect idle, ready to be scheduled again) if it turns out no signal
the effect read has actually changed -- e.g. it reads a `Computed` that recomputed to an equal
value.

Throws whatever the effect's function (or the cleanup before it) throws.
*/
let run: t => unit

/**
Stops the effect from rerunning, forgets every signal it was reading, disposes the effects its last
run created, and calls its pending cleanup function, if any. A disposed effect can't be revived
(create a new one instead); disposing it again does nothing.
*/
let dispose: t => unit

/** A scheduler, as a module -- what `Make` takes. */
module type Scheduler = {
  let schedule: scheduler
}

/** What `Make` produces: effects whose scheduler is already decided. */
module type S = {
  type t

  /** `EffectBase.make`, with this module's scheduler. */
  let make: (unit => unit) => t

  /** `EffectBase.makeWithCleanup`, with this module's scheduler. */
  let makeWithCleanup: (unit => option<unit => unit>) => t

  /** See `EffectBase.dispose`. */
  let dispose: t => unit
}

/** Builds an application's `Effect` module from the scheduler it wants every effect to use. */
module Make: (Scheduler: Scheduler) => (S with type t = t)
