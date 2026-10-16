/***
A circular buffer of the most recent diffs recorded for one `Atom` or `Computed`, letting
`getChangesSince` answer "everything that changed since epoch E" without keeping the
signal's entire history forever.
*/

/** What `getChangesSince` answers. Re-exported, and documented, as `Signal.diffsSince`. */
type diffsSince<'diff> =
  | Reset
  | Diffs(array<'diff>)

/** A buffer of diffs of type `'diff`. */
type t<'diff>

/** An empty buffer that retains the `capacity` most recent diffs. `capacity` must be positive. */
let make: int => t<'diff>

/**
Forgets every recorded diff. Any later `getChangesSince` reaching back before this point answers
`Reset`.
*/
let clear: t<'diff> => unit

/**
Records a change from `fromEpoch` to `toEpoch`. Entries are expected to chain: each one's
`fromEpoch` is the previous entry's `toEpoch` (the signal's `lastChangedEpoch` on either side of
the change). `getChangesSince` relies on that to replay a run of entries.

`diff` is `None` when there's nothing recordable -- no `computeDiff` was given, it returned
nothing itself, or there simply is no diff to attach -- and that clears the whole buffer
rather than leaving a gap: a later `getChangesSince` from before the gap must see `Reset`,
not an incomplete run of diffs that silently skips the change that happened here. Once the
buffer is full, the oldest entry is overwritten.
*/
let pushEntry: (t<'diff>, int, int, option<'diff>) => unit

/**
Everything that changed since `sinceEpoch`: `Diffs` holding every diff recorded after it,
oldest first (`Diffs([])` if nothing has changed since), or `Reset` if the buffer can't cover
that gap -- `sinceEpoch` is older than the oldest retained entry, or a change in between was
recorded without a diff (see `pushEntry`).
*/
let getChangesSince: (t<'diff>, int) => diffsSince<'diff>
