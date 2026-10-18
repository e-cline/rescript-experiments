/***
A mutable signal, updated directly via `set`/`update`. Every atom is also a read-only `Signal.t`
(`toSignal`), which is the interface derived signals and `AtomMap`/`ComputedMap` consume; see
`Signal`.

`t` is opaque: nothing outside this module needs (or should rely on) the underlying
representation, only the functions below and the `Signal.t` `toSignal` hands back.
*/

/** A mutable signal holding a `'value`, whose changes are described by diffs of type `'diff`. */
type t<'value, 'diff>

/**
Creates an atom holding the initial value -- the common case, with no diffing (so its diff type is
`unit`). See `makeIncremental` for the form `AtomMap` builds on.

- `name`: a human-readable identifier, used only for debugging.
- `equal`: compares the old and new value on `set`/`update` to decide whether it actually
  changed. Defaults to `===` -- physical equality for objects/arrays, value equality for
  primitives.
*/
let make: (~name: string=?, ~equal: ('value, 'value) => bool=?, 'value) => t<'value, unit>

/**
Creates an atom that can also record how its value changed, as diffs of type `'diff`, for
`getDiffSince` to replay.

- `name`, `equal`: as for `make`. The default `===` is also the right choice for a value like a
  `BTree.t`, where an update that changes nothing (e.g. `BTree.remove` of an absent key) hands back
  the very same tree (see `AtomMap`).
- `historyLength`: how many diffs to retain for `getDiffSince`. `0` (the default) keeps no
  history at all, so `getDiffSince` answers `Reset` for any earlier epoch.
- `computeDiff`: computes the diff to record for a change, given the previous value, the new
  value, and the epochs the change spans (from the previous change's epoch, to this one's),
  when `set`/`update` isn't given one explicitly. Only consulted if `historyLength` is greater
  than `0`.
*/
let makeIncremental: (
  ~name: string=?,
  ~equal: ('value, 'value) => bool=?,
  ~historyLength: int=?,
  ~computeDiff: ('value, 'value, int, int) => option<'diff>=?,
  'value,
) => t<'value, 'diff>

/**
The current value, establishing a dependency on this atom if called while a `Computed` or
effect is running: if the value later changes, that computed/effect is recomputed/rerun.
*/
let get: t<'value, 'diff> => 'value

/**
Like `get`, but never establishes a dependency -- for the rare case where the caller genuinely
shouldn't react to changes in this atom. Prefer `Untracked.run`, which is explicit about the
scope it applies to.
*/
let peek: t<'value, 'diff> => 'value

/** The epoch at which this atom's value last actually changed. */
let lastChangedEpoch: t<'value, 'diff> => int

/**
The diffs recorded between the given epoch and the atom's current value. See `Signal.diffsSince`.
*/
let getDiffSince: (t<'value, 'diff>, int) => Signal.diffsSince<'diff>

/**
Sets the atom to the given value. A no-op if `equal` says it's unchanged: nothing is notified, and
the *existing* value is kept.

`diff` is the diff to record for this change, if the atom keeps history (`historyLength > 0`).
It defaults to what `computeDiff` returns, if that was supplied; otherwise no diff is
recorded, and a later `getDiffSince` spanning this change answers `Reset`.

Throws if called while a `Computed` is being evaluated: compute functions must be pure.
*/
let set: (t<'value, 'diff>, ~diff: 'diff=?, 'value) => unit

/** Sets the atom to `updater(current value)`. See `set`. */
let update: (t<'value, 'diff>, ~diff: 'diff=?, 'value => 'value) => unit

/**
This atom as a read-only `Signal.t` -- e.g. to hand to a `ComputedMap` operation, or anything else
that shouldn't be able to write to it. Costs nothing: it's the same object, so the result is `===`
however many times this is called.
*/
external toSignal: t<'value, 'diff> => Signal.t<'value, 'diff> = "%identity"
