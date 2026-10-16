/***
A single global logical clock, shared by every `Atom`/`Computed` in the process: each write
to an atom advances it once, and every signal that changes as a result -- the atom itself,
and any computed that recomputes to a new value as a result -- stamps its own change
with that same value. Two signals sharing an epoch is exactly what lets a downstream
consumer ask "did anything change since the last time I looked," rather than needing
wall-clock time or a per-signal counter that can't be compared across signals.
*/

/** The most recent epoch handed out by `advance` (`0` before the first one). */
let current: ref<int>

/** Advances the clock by one and returns the new epoch. */
let advance: unit => int
