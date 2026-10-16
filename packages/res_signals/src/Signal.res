// See `Signal.resi`.

type diffsSince<'diff> = HistoryBuffer.diffsSince<'diff> =
  | Reset
  | Diffs(array<'diff>)

type t<'value, 'diff> = SignalCore.t<'value, 'diff>

let name = (self: t<'value, 'diff>): string => self.name
let get = SignalCore.get
let peek = SignalCore.peek
let lastChangedEpoch = SignalCore.lastChangedEpoch
let getDiffSince = SignalCore.getDiffSince
