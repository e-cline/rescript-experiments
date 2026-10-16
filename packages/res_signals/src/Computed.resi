/***
A signal derived from other signals, recomputed on demand. Unlike `Atom`, there's no separate
wrapper type: `make`/`makeIncremental` hand back a plain `Signal.t` directly, since a computed
has no write API of its own to hide behind a narrower interface.

A computed only recomputes when something it read has actually changed, and only when it is
next read. A computation that (directly or indirectly) reads its own signal throws, rather than
recursing forever.

There's nothing to dispose: the signals a computed reads only hold on to it while something (an
effect, or another computed an effect reads) is in turn consuming it. Otherwise, dropping the last
reference to a computed is enough for it to be garbage collected.
*/

/**
What a `makeIncremental` compute function returns for one computation: just the new `value`
(`Value`), or the new value together with the exact diff describing how it changed from the
previous one (`ValueWithDiff`) -- for a compute function that, like `AtomMap`'s
`mapValues`/`filterMap`/`map`, already knows its diff for free as a byproduct of computing the
value incrementally, and so has no reason to let `computeDiff` re-derive it from scratch
afterward.
*/
type result<'value, 'diff> =
  | Value('value)
  | ValueWithDiff('value, 'diff)

/**
Creates a computed signal, calling the compute function to derive its value from other
signals -- reading them inside it is what makes this signal recompute when they change. The
compute function must be pure: no writing to atoms, no other side effects.

This is the incremental/diffable form, used by `AtomMap`/`ComputedMap`'s derived-map operations.
The compute function receives the previous value (`None` on the first computation) and the epoch
at which the previous computation ran (`-1` on the first), so it can, e.g., ask *other* signals
for `getDiffSince(thatEpoch)` and update the previous value incrementally instead of recomputing
from scratch. See `make` for the common case that needs none of this.

- `name`: a human-readable identifier, used in debugging and error messages.
- `equal`: compares the old and new value to decide whether it actually changed. Defaults to
  `===`.
- `historyLength`: how many diffs to retain for `getDiffSince`. `0` (the default) keeps no history
  at all.
- `computeDiff`: computes the diff to record for a change, when the compute function returns a
  plain `Value` rather than a `ValueWithDiff`. Only consulted if `historyLength` is greater than
  `0`.
*/
let makeIncremental: (
  ~name: string=?,
  ~equal: ('value, 'value) => bool=?,
  ~historyLength: int=?,
  ~computeDiff: ('value, 'value, int, int) => option<'diff>=?,
  (option<'value>, int) => result<'value, 'diff>,
) => Signal.t<'value, 'diff>

/**
Creates a computed signal from a plain `unit => 'value` function -- the common case, with no
previous-value access and no diffing (so its diff type is `unit`). See `makeIncremental` for the
form `AtomMap`/`ComputedMap` build on.
*/
let make: (
  ~name: string=?,
  ~equal: ('value, 'value) => bool=?,
  unit => 'value,
) => Signal.t<'value, unit>
