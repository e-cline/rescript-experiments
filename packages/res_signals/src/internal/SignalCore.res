/***
The one concrete representation behind `Signal.t` and `Atom.t` (which is why `Atom.toSignal` costs
nothing): a `Node.t` cell for the graph, plus the typed value and diff history the cell itself
doesn't carry. `Atom`/`Computed` create these; `Signal` only reads them.
*/

type t<'value, 'diff> = {
  cell: Node.t,
  name: string,
  /**
  The current value. For a computed, a placeholder until its first computation
  (`cell.lastComputedEpoch < 0`), and only current once `Node.ensureFresh` has run.
  */
  mutable value: 'value,
  equal: ('value, 'value) => bool,
  computeDiff: option<('value, 'value, int, int) => option<'diff>>,
  history: option<HistoryBuffer.t<'diff>>,
}

let strictEqual = (a, b) => a === b

let make = (
  kind: Node.kind,
  ~name: string,
  ~equal: option<('value, 'value) => bool>,
  ~historyLength: int,
  ~computeDiff: option<('value, 'value, int, int) => option<'diff>>,
  initial: 'value,
): t<'value, 'diff> => {
  cell: Node.make(kind),
  name,
  value: initial,
  equal: switch equal {
  | Some(equal) => equal
  | None => strictEqual
  },
  computeDiff,
  history: historyLength > 0 ? Some(HistoryBuffer.make(historyLength)) : None,
}

let get = (self: t<'value, 'diff>): 'value => {
  Node.ensureFresh(self.cell)
  Node.track(self.cell)
  self.value
}

let peek = (self: t<'value, 'diff>): 'value => {
  Node.ensureFresh(self.cell)
  self.value
}

let lastChangedEpoch = (self: t<'value, 'diff>): int => self.cell.lastChangedEpoch

let getDiffSince = (self: t<'value, 'diff>, epoch: int): HistoryBuffer.diffsSince<'diff> =>
  if epoch >= self.cell.lastChangedEpoch {
    Diffs([])
  } else {
    switch self.history {
    | None => Reset
    | Some(history) => HistoryBuffer.getChangesSince(history, epoch)
    }
  }

/**
Replaces the value with one the caller has already established is different, as of `epoch`, and
records the change in the history buffer (if there is one): with `diff` if given, otherwise with
whatever `computeDiff` makes of it.
*/
let change = (self: t<'value, 'diff>, value: 'value, ~diff: option<'diff>, epoch: int): unit => {
  let previous = self.value
  // From the epoch of the previous *change*: for a computed, a recompute in between that produced
  // an equal value recorded no entry, and starting this one any later would leave a gap in the
  // buffer that a consumer last in sync from before that recompute falls into (and so needlessly
  // gets `Reset`).
  let fromEpoch = self.cell.lastChangedEpoch
  self.value = value
  self.cell.lastChangedEpoch = epoch
  switch self.history {
  | None => ()
  | Some(history) =>
    let recorded = switch diff {
    | Some(_) => diff
    | None =>
      switch self.computeDiff {
      | Some(computeDiff) => computeDiff(previous, value, fromEpoch, epoch)
      | None => None
      }
    }
    HistoryBuffer.pushEntry(history, fromEpoch, epoch, recorded)
  }
}
