// See `Node.resi` for what the graph is and how each function behaves; the
// comments in this file are implementation notes.

type kind =
  | Atom
  | Computed
  | Effect

type rec t = {
  id: int,
  kind: kind,
  mutable dirty: bool,
  mutable lastChangedEpoch: int,
  mutable lastComputedEpoch: int,
  mutable verifiedEpoch: int,
  mutable running: bool,
  mutable trackedInRun: int,
  sources: array<t>,
  sourceSlots: array<int>,
  consumers: array<t>,
  consumerSlots: array<int>,
  mutable recompute: unit => unit,
  mutable notify: unit => unit,
  mutable disposed: bool,
}

@set external truncate: (array<'a>, int) => unit = "length"

/** Source of each new cell's unique `id`. */
let nextId = ref(0)

/** Shared by every cell that has no `recompute`/`notify` of its own. */
let noop = () => ()

let make = (kind: kind): t => {
  nextId := nextId.contents + 1
  {
    id: nextId.contents,
    kind,
    dirty: false,
    lastChangedEpoch: 0,
    lastComputedEpoch: kind === Computed ? -1 : 0,
    verifiedEpoch: -1,
    running: false,
    trackedInRun: 0,
    sources: [],
    sourceSlots: [],
    consumers: [],
    consumerSlots: [],
    recompute: noop,
    notify: noop,
    disposed: false,
  }
}

let activeConsumer: ref<option<t>> = ref(None)

let batchDepth = ref(0)

// The state of the innermost `runTracked` call in progress; each call saves and restores the
// enclosing one's.

/** Source of each `runTracked` call's unique run number. */
let nextRun = ref(0)

/** The current run's number: what `track` stamps a source's `trackedInRun` with. */
let currentRun = ref(0)

/**
How many of the active consumer's previous sources this run has read again so far, in the same
order -- so `sources[0..runCursor)` are edges this run is keeping exactly as they were.
*/
let runCursor = ref(0)

/**
`-1` while every read so far has matched the previous run's sources in order. Once one doesn't,
this is the length `sources` had at that point: `sources[runCursor..runTailEnd)` are then the
previous run's leftover edges (dropped when the run ends), and everything from `runTailEnd` on is
an edge added by this run.
*/
let runTailEnd = ref(-1)

/**
Whether the cell is linked into its sources' `consumers`. An effect is, until disposed; a computed
only while something consumes it in turn.
*/
let isLive = (cell: t): bool =>
  switch cell.kind {
  | Effect => !cell.disposed
  | Atom | Computed => Array.length(cell.consumers) > 0
  }

/**
Computeds that `link` has just made live, or `unlink` idle, and whose own sources still have to
follow. A module-level array, reused by every call (it's always empty between them), rather than
recursion: a long chain of computeds would otherwise overflow the stack part-way through, leaving
the graph half-linked.
*/
let cascadeStack: array<t> = []

let linkEdge = (consumer: t, index: int): unit => {
  let source = Array.getUnsafe(consumer.sources, index)
  let slot = Array.length(source.consumers)
  Array.push(source.consumers, consumer)
  Array.push(source.consumerSlots, index)
  Array.setUnsafe(consumer.sourceSlots, index, slot)
  if slot === 0 && source.kind === Computed {
    Array.push(cascadeStack, source)
  }
}

/**
Adds the consumer to the `consumers` of its source at `index`, recording on each side where the
edge sits on the other. A computed gaining its first consumer this way goes live itself.
*/
let link = (consumer: t, index: int): unit => {
  linkEdge(consumer, index)
  while Array.length(cascadeStack) > 0 {
    let last = Array.length(cascadeStack) - 1
    let cell = Array.getUnsafe(cascadeStack, last)
    truncate(cascadeStack, last)
    for i in 0 to Array.length(cell.sources) - 1 {
      linkEdge(cell, i)
    }
  }
}

let unlinkEdge = (consumer: t, index: int): unit => {
  let source = Array.getUnsafe(consumer.sources, index)
  let slot = Array.getUnsafe(consumer.sourceSlots, index)
  let consumers = source.consumers
  let slots = source.consumerSlots
  let last = Array.length(consumers) - 1
  if slot !== last {
    let moved = Array.getUnsafe(consumers, last)
    let movedIndex = Array.getUnsafe(slots, last)
    Array.setUnsafe(consumers, slot, moved)
    Array.setUnsafe(slots, slot, movedIndex)
    Array.setUnsafe(moved.sourceSlots, movedIndex, slot)
  }
  truncate(consumers, last)
  truncate(slots, last)
  if last === 0 && source.kind === Computed {
    Array.push(cascadeStack, source)
  }
}

/**
Removes the consumer from the `consumers` of its source at `index`, in constant time: the last
consumer in that list is moved into the vacated slot (and told its new position). Leaves
`consumer.sources`/`sourceSlots` themselves alone -- the caller is about to overwrite or truncate
them. A computed losing its last consumer this way goes idle itself.
*/
let unlink = (consumer: t, index: int): unit => {
  unlinkEdge(consumer, index)
  while Array.length(cascadeStack) > 0 {
    let last = Array.length(cascadeStack) - 1
    let cell = Array.getUnsafe(cascadeStack, last)
    truncate(cascadeStack, last)
    for i in 0 to Array.length(cell.sources) - 1 {
      unlinkEdge(cell, i)
    }
    truncate(cell.sourceSlots, 0)

    // From here on nothing marks it dirty, so `ensureFresh` goes by `verifiedEpoch` instead. If
    // it's dirty already it stays so, and is checked on its next read regardless.
    if !cell.dirty {
      cell.verifiedEpoch = Epoch.current.contents
    }
  }
}

let track = (source: t): unit =>
  switch activeConsumer.contents {
  | None => ()
  | Some(consumer) =>
    if source.trackedInRun !== currentRun.contents && !consumer.disposed {
      source.trackedInRun = currentRun.contents
      let sources = consumer.sources
      let cursor = runCursor.contents
      if (
        runTailEnd.contents < 0 &&
        cursor < Array.length(sources) &&
        Array.getUnsafe(sources, cursor) === source
      ) {
        runCursor := cursor + 1
      } else {
        if runTailEnd.contents < 0 {
          runTailEnd := Array.length(sources)
        }
        Array.push(sources, source)
        if isLive(consumer) {
          link(consumer, Array.length(sources) - 1)
        }
      }
    }
  }

/**
Ends a run: drops the previous run's sources that this one didn't read again
(`sources[keep..tailEnd)`), and moves the ones it newly added down into their place.
*/
let prune = (consumer: t, keep: int, tailEnd: int): unit => {
  let sources = consumer.sources
  let length = Array.length(sources)
  let tailEnd = tailEnd < 0 ? length : tailEnd
  if keep < tailEnd {
    let live = isLive(consumer)

    // Only now that every edge this run added is in place: a source that was dropped but then
    // read again never loses its last consumer in between, and so never goes idle just to go live
    // again.
    if live {
      for i in keep to tailEnd - 1 {
        unlink(consumer, i)
      }
    }
    let removed = tailEnd - keep
    for from in tailEnd to length - 1 {
      let to = from - removed
      let source = Array.getUnsafe(sources, from)
      Array.setUnsafe(sources, to, source)
      if live {
        let slot = Array.getUnsafe(consumer.sourceSlots, from)
        Array.setUnsafe(consumer.sourceSlots, to, slot)
        Array.setUnsafe(source.consumerSlots, slot, to)
      }
    }
    truncate(sources, length - removed)
    if live {
      truncate(consumer.sourceSlots, length - removed)
    }
  }
}

let runTracked = (consumer: t, f: unit => 'a): 'a => {
  let previousActive = activeConsumer.contents
  let previousRun = currentRun.contents
  let previousCursor = runCursor.contents
  let previousTailEnd = runTailEnd.contents
  nextRun := nextRun.contents + 1
  activeConsumer := Some(consumer)
  currentRun := nextRun.contents
  runCursor := 0
  runTailEnd := -1
  consumer.running = true
  let finish = () => {
    let keep = runCursor.contents
    let tailEnd = runTailEnd.contents
    activeConsumer := previousActive
    currentRun := previousRun
    runCursor := previousCursor
    runTailEnd := previousTailEnd
    consumer.running = false

    // A disposed effect (possibly by its own body, part-way through this run) has no sources
    // left to tidy.
    if !consumer.disposed {
      prune(consumer, keep, tailEnd)
    }
  }
  switch f() {
  | result =>
    finish()
    result
  | exception e =>
    finish()
    throw(e)
  }
}

/**
Effects that have become due but not yet been notified, in the order they were marked dirty.
`markDirty` already guards against pushing the same effect twice (an already-dirty effect is
skipped), so membership is never duplicated. `settle` works through it front to back by advancing
`pendingIndex`, and only empties it once it's done.
*/
let pendingEffects: array<t> = []

/** The position in `pendingEffects` of the next effect `settle` will notify. */
let pendingIndex = ref(0)

/**
Cells whose consumers `markDirty` still has to visit. A module-level array, reused by every call
(it's always empty between them), rather than recursion: a long chain of computeds would otherwise
overflow the stack part-way through marking, leaving the graph half-marked.
*/
let markStack: array<t> = []

let markDirty = (source: t): unit => {
  Array.push(markStack, source)
  while Array.length(markStack) > 0 {
    let last = Array.length(markStack) - 1
    let consumers = Array.getUnsafe(markStack, last).consumers
    truncate(markStack, last)
    for i in 0 to Array.length(consumers) - 1 {
      let consumer = Array.getUnsafe(consumers, i)
      if !consumer.dirty {
        consumer.dirty = true
        switch consumer.kind {
        | Atom => () // unreachable: nothing with kind Atom is ever a consumer
        | Computed => Array.push(markStack, consumer)
        | Effect => Array.push(pendingEffects, consumer)
        }
      }
    }
  }
}

let rec ensureFresh = (cell: t): unit =>
  if (
    cell.kind === Computed &&
      (cell.dirty ||
      (cell.verifiedEpoch !== Epoch.current.contents && Array.length(cell.consumers) === 0))
  ) {
    // `running` means this is the cell's own computation reading it: `recompute` is what reports
    // that as a cycle.
    if cell.running || cell.lastComputedEpoch < 0 || sourceChanged(cell) {
      cell.recompute()
    }
    cell.dirty = false
    cell.verifiedEpoch = Epoch.current.contents
  }
and sourceChanged = (cell: t): bool => {
  let sources = cell.sources
  let changed = ref(false)
  let i = ref(0)
  while !changed.contents && i.contents < Array.length(sources) {
    let source = Array.getUnsafe(sources, i.contents)
    ensureFresh(source)
    changed := source.lastChangedEpoch > cell.lastComputedEpoch
    i := i.contents + 1
  }
  changed.contents
}

/**
Guards `settle` against being re-entered while it's already draining `pendingEffects` -- a
`notify` is free to rerun its effect on the spot, whose body is free to write an atom, and that
write's own call to `settle` must not start a second, concurrent drain of the same queue. A write
during a drain just appends more work for the *current* drain to pick up -- no nested drain is ever
needed.
*/
let isSettling = ref(false)

/**
How many passes over the effects that became due during the previous pass `settle` makes before
giving up. Far more than any chain of effects legitimately triggering each other needs; reaching
it means some effect keeps writing a signal that it (or an effect it triggers) reads, without ever
settling, which would otherwise never return.
*/
let maxSettlePasses = 100

let settle = (): unit =>
  if batchDepth.contents === 0 && !isSettling.contents {
    isSettling := true
    let firstError: ref<option<exn>> = ref(None)
    let pass = ref(1)
    // Where the effects that were already due when the current pass started end.
    let passEnd = ref(Array.length(pendingEffects))
    while pendingIndex.contents < Array.length(pendingEffects) && pass.contents <= maxSettlePasses {
      if pendingIndex.contents === passEnd.contents {
        pass := pass.contents + 1
        passEnd := Array.length(pendingEffects)
      } else {
        let effect = Array.getUnsafe(pendingEffects, pendingIndex.contents)
        pendingIndex := pendingIndex.contents + 1
        if !effect.disposed {
          // One failing must not leave the others waiting -- or this module's own state
          // (`isSettling`, the queue) unfinished.
          switch effect.notify() {
          | () => ()
          | exception error =>
            if Option.isNone(firstError.contents) {
              firstError := Some(error)
            }
          }
        }
      }
    }
    // Everything, unless it gave up: then whatever is still due stays queued.
    let gaveUp = pendingIndex.contents < Array.length(pendingEffects)
    Array.splice(pendingEffects, ~start=0, ~remove=pendingIndex.contents, ~insert=[])
    pendingIndex := 0
    isSettling := false
    switch firstError.contents {
    | Some(error) => throw(error)
    | None =>
      if gaveUp {
        JsError.throwWithMessage(
          `Effects were still triggering each other after ${Int.toString(
              maxSettlePasses,
            )} passes: an effect is probably writing a signal that it, or an effect it triggers, reads, without ever settling. The effects still due will be notified after the next write.`,
        )
      }
    }
  }

let disconnect = (cell: t): unit => {
  for i in 0 to Array.length(cell.sources) - 1 {
    unlink(cell, i)
  }
  truncate(cell.sources, 0)
  truncate(cell.sourceSlots, 0)
}
