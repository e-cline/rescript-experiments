// See `EffectBase.resi` for what an effect is and how each function behaves.

type rec t = {
  cell: Node.t,
  body: unit => option<unit => unit>,
  /** What the last run's body returned, until it's been called. */
  mutable cleanup: option<unit => unit>,
  /** The effects created during the last run, in order, until they've been disposed. */
  mutable children: array<t>,
}

type scheduler = t => unit

/**
The effect whose body is currently running, if any: the owner of any effect created meanwhile.
Separate from `Node.activeConsumer` -- `Untracked.run` stops reads being tracked, but an effect
created inside it is still the running effect's to dispose.
*/
let owner: ref<option<t>> = ref(None)

/** Runs a cleanup function with no owner and no tracking: it belongs to a run that's over. */
let runDetached = (f: unit => unit): unit => {
  let previousOwner = owner.contents
  owner := None
  switch Untracked.run(f) {
  | () => owner := previousOwner
  | exception error =>
    owner := previousOwner
    throw(error)
  }
}

/**
Undoes what the last run left behind: disposes the effects it created (most recent first), then
calls its cleanup function. Finishes all of that even if part of it throws, then rethrows the
first exception.
*/
let rec teardown = (self: t): unit => {
  let firstError: ref<option<exn>> = ref(None)
  let note = (error: exn) =>
    if Option.isNone(firstError.contents) {
      firstError := Some(error)
    }
  let children = self.children
  if Array.length(children) > 0 {
    self.children = []
    for i in Array.length(children) - 1 downto 0 {
      switch dispose(Array.getUnsafe(children, i)) {
      | () => ()
      | exception error => note(error)
      }
    }
  }
  switch self.cleanup {
  | None => ()
  | Some(cleanup) =>
    self.cleanup = None
    switch runDetached(cleanup) {
    | () => ()
    | exception error => note(error)
    }
  }
  switch firstError.contents {
  | Some(error) => throw(error)
  | None => ()
  }
}
and dispose = (self: t): unit =>
  if !self.cell.disposed {
    self.cell.disposed = true
    Node.disconnect(self.cell)
    teardown(self)
  }

let execute = (self: t): unit => {
  teardown(self)

  // Stamped before the body runs, not after: the body is free to write an atom it has already
  // read, and that write (at a later epoch) must still count as a change this run hasn't seen.
  self.cell.lastComputedEpoch = Epoch.current.contents
  let previousOwner = owner.contents
  owner := Some(self)
  switch Node.runTracked(self.cell, self.body) {
  | cleanup =>
    owner := previousOwner
    self.cleanup = cleanup
  | exception error =>
    owner := previousOwner
    throw(error)
  }

  // The body disposed its own effect: nothing will come back for what this run left behind.
  if self.cell.disposed {
    teardown(self)
  }
}

let makeWithCleanup = (~scheduler: scheduler, body: unit => option<unit => unit>): t => {
  let cell = Node.make(Node.Effect)
  let self = {cell, body, cleanup: None, children: []}
  cell.notify = () => scheduler(self)
  // Effects run immediately on creation, not just when something they depend on later changes --
  // there is no earlier value to have reacted to yet.
  switch execute(self) {
  | () => ()
  | exception error =>
    // The caller never gets a handle to dispose it with, so it mustn't stay subscribed.
    switch dispose(self) {
    | () => ()
    | exception _ => ()
    }
    throw(error)
  }
  switch owner.contents {
  | Some(parent) => Array.push(parent.children, self)
  | None => ()
  }
  self
}

let make = (~scheduler: scheduler, body: unit => unit): t =>
  makeWithCleanup(~scheduler, () => {
    body()
    None
  })

let run = (self: t): unit => {
  let cell = self.cell
  if cell.dirty && !cell.disposed {
    cell.dirty = false
    if Node.sourceChanged(cell) {
      execute(self)
    }
  }
}

module type Scheduler = {
  let schedule: scheduler
}

module type S = {
  type t
  let make: (unit => unit) => t
  let makeWithCleanup: (unit => option<unit => unit>) => t
  let dispose: t => unit
}

type effect = t

module Make = (Scheduler: Scheduler): (S with type t = effect) => {
  type t = effect
  let make = body => make(~scheduler=Scheduler.schedule, body)
  let makeWithCleanup = body => makeWithCleanup(~scheduler=Scheduler.schedule, body)
  let dispose = dispose
}
