// See `Atom.resi` for what an atom is and how each function behaves.

type t<'value, 'diff> = SignalCore.t<'value, 'diff>

let makeIncremental = (
  ~name: string="",
  ~equal: option<('value, 'value) => bool>=?,
  ~historyLength: int=0,
  ~computeDiff: option<('value, 'value, int, int) => option<'diff>>=?,
  initial: 'value,
): t<'value, 'diff> =>
  SignalCore.make(Node.Atom, ~name, ~equal, ~historyLength, ~computeDiff, initial)

let make = (~name: string="", ~equal: option<('value, 'value) => bool>=?, initial: 'value): t<
  'value,
  unit,
> => SignalCore.make(Node.Atom, ~name, ~equal, ~historyLength=0, ~computeDiff=None, initial)

// Not `SignalCore.get`/`peek`: an atom's value is always current, so there's nothing for
// `Node.ensureFresh` to do.
let get = (self: t<'value, 'diff>): 'value => {
  Node.track(self.cell)
  self.value
}

let peek = (self: t<'value, 'diff>): 'value => self.value

let lastChangedEpoch = SignalCore.lastChangedEpoch

let getDiffSince = SignalCore.getDiffSince

/**
Throws if an atom is written while a `Computed` is being evaluated. Compute functions must be
pure: writing an atom from inside one would mark this atom's consumers dirty (and, outside a
batch, notify effects) while a *different* signal's computation is still on the stack, part-way
through building a value nothing has read yet. (An effect's body, by contrast, is free to write
atoms -- see `Node.settle`.)
*/
let assertWritable = (): unit =>
  switch Node.activeConsumer.contents {
  | Some({kind: Node.Computed}) =>
    JsError.throwWithMessage(
      "Cannot set an atom while a computed signal is being evaluated: compute functions must be pure.",
    )
  | _ => ()
  }

let set = (self: t<'value, 'diff>, ~diff: option<'diff>=?, value: 'value): unit => {
  assertWritable()
  if !self.equal(self.value, value) {
    SignalCore.change(self, value, ~diff, Epoch.advance())
    Node.markDirty(self.cell)
    Node.settle()
  }
}

let update = (self: t<'value, 'diff>, ~diff: option<'diff>=?, updater: 'value => 'value): unit =>
  set(self, ~diff?, updater(self.value))

external toSignal: t<'value, 'diff> => Signal.t<'value, 'diff> = "%identity"
