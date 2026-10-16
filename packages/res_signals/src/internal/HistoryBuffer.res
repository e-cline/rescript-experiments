// An entry's diff is a plain `option`, with `None` meaning "no diff, must
// reset" (see `pushEntry`'s documentation in `HistoryBuffer.resi`), rather
// than a separate sentinel value.
//
// Consecutive entries chain (`entry[k+1].fromEpoch === entry[k].toEpoch`);
// `getChangesSince` relies on that to find the run of entries covering a
// requested epoch.

type diffsSince<'diff> =
  | Reset
  | Diffs(array<'diff>)

/**
One recorded change: the diff describing how a signal's value went from `fromEpoch` to `toEpoch`.
*/
type entry<'diff> = {
  fromEpoch: int,
  toEpoch: int,
  diff: 'diff,
}

/**
The circular buffer itself: `slots` holds up to `capacity` entries, and `index` is the slot the
*next* entry will be written to (so the newest entry is at `index - 1`, wrapping around).
Slots that haven't been written since creation (or since `clear`) are `None`.
*/
type t<'diff> = {
  capacity: int,
  mutable index: int,
  mutable slots: array<option<entry<'diff>>>,
}

let make = (capacity: int): t<'diff> => {
  capacity,
  index: 0,
  slots: Belt.Array.make(capacity, None),
}

let clear = (self: t<'diff>): unit => {
  self.index = 0
  self.slots = Belt.Array.make(self.capacity, None)
}

let pushEntry = (self: t<'diff>, fromEpoch: int, toEpoch: int, diff: option<'diff>): unit =>
  switch diff {
  | None => clear(self)
  | Some(diff) =>
    Belt.Array.setUnsafe(self.slots, self.index, Some({fromEpoch, toEpoch, diff}))
    self.index = mod(self.index + 1, self.capacity)
  }

let getChangesSince = (self: t<'diff>, sinceEpoch: int): diffsSince<'diff> => {
  let rec loop = (i: int): diffsSince<'diff> =>
    if i >= self.capacity {
      Reset
    } else {
      let offset = mod(self.index - 1 + self.capacity - i, self.capacity)
      switch Array.getUnsafe(self.slots, offset) {
      | None => Reset
      | Some({toEpoch}) if i === 0 && sinceEpoch >= toEpoch => Diffs([])
      | Some({fromEpoch, toEpoch}) if fromEpoch <= sinceEpoch && sinceEpoch < toEpoch =>
        Diffs(
          Belt.Array.makeBy(i + 1, j => {
            let entry = switch Array.getUnsafe(self.slots, mod(offset + j, self.capacity)) {
            | Some(entry) => entry
            | None => JsError.throwWithMessage("HistoryBuffer: contiguity invariant violated")
            }
            entry.diff
          }),
        )
      | Some(_) => loop(i + 1)
      }
    }
  loop(0)
}
