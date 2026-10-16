// See `Computed.resi` for what a computed signal is and how `make`/`makeIncremental` behave.

type result<'value, 'diff> =
  | Value('value)
  | ValueWithDiff('value, 'diff)

external toSignal: SignalCore.t<'value, 'diff> => Signal.t<'value, 'diff> = "%identity"

/** Stands in for a computed's value until its first computation; never read before then. */
external uncomputed: unit => 'value = "%identity"

/**
Runs a compute function with the signal's cell tracking what it reads. Throws instead if that
computation is already running, i.e. it read its own signal (directly, or through others):
`Node.ensureFresh` deliberately sends that case here, since it can't be told apart from an
ordinary stale read any earlier, and would otherwise recurse forever.
*/
let runCompute = (self: SignalCore.t<'value, 'diff>, compute: unit => 'a): 'a => {
  if self.cell.running {
    JsError.throwWithMessage(
      `Detected cycle in computations: "${self.name}" was read while computing its own value.`,
    )
  }
  Node.runTracked(self.cell, compute)
}

/**
Takes on a freshly computed value. This never calls `Node.markDirty` itself: every cell that
could possibly need to redo work because of a change here was already marked dirty, transitively,
by whatever `Atom.set` started this update (or, if this computed is idle, finds out for itself the
same way this one did) -- see `Node.markDirty`'s own comment.
*/
let commit = (self: SignalCore.t<'value, 'diff>, value: 'value, ~diff: option<'diff>): unit => {
  let cell = self.cell
  let epoch = Epoch.current.contents
  let isFirst = cell.lastComputedEpoch < 0
  cell.lastComputedEpoch = epoch
  if isFirst {
    // No history entry for the first computation: there's nothing to diff against.
    self.value = value
    cell.lastChangedEpoch = epoch
  } else if !self.equal(self.value, value) {
    SignalCore.change(self, value, ~diff, epoch)
  }
}

let makeIncremental = (
  ~name: string="",
  ~equal: option<('value, 'value) => bool>=?,
  ~historyLength: int=0,
  ~computeDiff: option<('value, 'value, int, int) => option<'diff>>=?,
  compute: (option<'value>, int) => result<'value, 'diff>,
): Signal.t<'value, 'diff> => {
  let self = SignalCore.make(
    Node.Computed,
    ~name,
    ~equal,
    ~historyLength,
    ~computeDiff,
    uncomputed(),
  )
  self.cell.recompute = () => {
    let previousComputedEpoch = self.cell.lastComputedEpoch
    let previous = previousComputedEpoch < 0 ? None : Some(self.value)
    switch runCompute(self, () => compute(previous, previousComputedEpoch)) {
    | Value(value) => commit(self, value, ~diff=None)
    | ValueWithDiff(value, diff) => commit(self, value, ~diff=Some(diff))
    }
  }
  toSignal(self)
}

// Not `makeIncremental` with a wrapped compute function: this is the common case, and going
// through it would cost a `Value` allocation and an extra closure on every recompute.
let make = (
  ~name: string="",
  ~equal: option<('value, 'value) => bool>=?,
  compute: unit => 'value,
): Signal.t<'value, unit> => {
  let self = SignalCore.make(
    Node.Computed,
    ~name,
    ~equal,
    ~historyLength=0,
    ~computeDiff=None,
    uncomputed(),
  )
  self.cell.recompute = () => commit(self, runCompute(self, compute), ~diff=None)
  toSignal(self)
}
