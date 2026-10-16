/***
The shared read-only view of every reactive value in this package: what a `Computed` is, and what
`Atom.toSignal` turns an atom into. Derived-map code (see `AtomMap`/`ComputedMap`) is written
against this, so it accepts either one identically.

`t` is opaque. Signals come from `Atom.toSignal` and `Computed.make`/`makeIncremental`.
*/

/**
What `getDiffSince` answers: either every diff recorded since the requested epoch, oldest first, or
`Reset` when the signal can't (or was never configured to) cover that gap -- e.g. no history buffer
was requested, the epoch is older than the buffer's capacity, or a change along the way genuinely
couldn't be expressed as a diff. `Reset` always means "rebuild from `get`'s current value instead,"
never "nothing changed" -- `Diffs([])` is what "nothing changed since then" looks like.
*/
type diffsSince<'diff> = HistoryBuffer.diffsSince<'diff> =
  | Reset
  | Diffs(array<'diff>)

/**
A read-only reactive value of type `'value`, whose changes are described by diffs of type `'diff`
(`unit` for a signal that doesn't record any).
*/
type t<'value, 'diff>

/** A human-readable identifier, used only for debugging -- it doesn't need to be unique. */
let name: t<'value, 'diff> => string

/**
The current value, establishing a dependency on this signal if called while a `Computed` or
effect is running: if the value later changes, that computed/effect is recomputed/rerun.
*/
let get: t<'value, 'diff> => 'value

/**
Like `get`, but never establishes a dependency -- for the rare case where the caller genuinely
shouldn't react to changes in this signal. Prefer `Untracked.run`, which is explicit about the
scope it applies to.
*/
let peek: t<'value, 'diff> => 'value

/**
The epoch at which this signal's value last actually changed (not merely recomputed to an equal
value).
*/
let lastChangedEpoch: t<'value, 'diff> => int

/** The diffs recorded between the given epoch and this signal's current value. See `diffsSince`. */
let getDiffSince: (t<'value, 'diff>, int) => diffsSince<'diff>
