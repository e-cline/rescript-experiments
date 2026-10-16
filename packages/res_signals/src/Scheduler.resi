/***
Ready-made schedulers for `EffectBase.Make`. An application is free to write its own instead: a
scheduler is just a function that, handed a due effect, arranges for `EffectBase.run` to be called
on it -- see `EffectBase.scheduler`.
*/

/**
Reruns a due effect synchronously: as soon as the write that made it due returns, or when the
outermost `Batch.run` around it exits. Effects run in the order they became due; a write made from
inside an effect's body doesn't run the effects it triggers on the spot, but queues them behind the
ones already due.

If an effect throws, the others due still run, and then the exception propagates out of the
`Atom.set`/`Batch.run` that triggered them (the first one, if several threw).

Effects that keep triggering each other without settling -- most simply, one that writes a signal
it reads, to a different value every time -- don't hang: after 100 rounds of effects making each
other due, the write that started it throws instead.
*/
module Sync: EffectBase.Scheduler

/**
Reruns due effects in a microtask (`queueMicrotask`), so any number of writes made in the same
synchronous stretch of code -- `Batch.run` or not -- rerun each effect once, after that code has
finished. Effects run in the order they became due.

There's at most one such microtask queued at a time: every effect due shares it, and so do the
effects those make due in turn, which run later in the same microtask rather than in a new one.

If an effect throws, the others due still run. Each exception is then rethrown from a microtask of
its own, to be reported however the host reports an uncaught one (nothing is there to catch it).

Effects that keep triggering each other without settling -- most simply, one that writes a signal
it reads, to a different value every time -- don't hold up the event loop forever: after 100 rounds
of effects making each other due within one microtask, it stops and reports an error the same way.
The effects still due at that point rerun the next time any effect is scheduled.
*/
module Microtask: EffectBase.Scheduler
