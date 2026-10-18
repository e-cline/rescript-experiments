/***
The reactive dependency graph underneath `Atom`/`Computed`/`EffectBase`: plain mutable records
("cells"), linked to each other by ordinary array membership (see "Edges" below), with no
scheduler of its own: when an `Effect` cell becomes due, all this module does is tell it so (see
`notify`/`settle`). Deciding when it then actually reruns is the job of whatever scheduler the
effect was created with -- see `EffectBase`.

A cell doesn't carry its own *value* (that stays in the typed `SignalCore.t` that owns it); it only
carries the untyped graph shape (`sources`/`consumers`) plus the epoch bookkeeping needed to decide,
generically, whether an out-of-date `Computed` actually needs to redo its work (see `ensureFresh`)
and the closures its owner fills in after creating the cell: `recompute` (Computed only, by
`Computed`) and `notify` (Effect only, by `EffectBase`).

This is the "internal public API" that `Atom`/`Computed`/`EffectBase`/`Batch` are meant to use.
Unlike a `.resi` for a package's own public surface, it isn't meant to hide `t`'s fields from those
sibling files (they need to read/write `recompute`/`notify`/`disposed` directly to do their work),
just to document, in one place, what this module considers its own supported surface.

## Edges

An edge between a consumer and one of its sources is recorded on both sides: the source appears in
the consumer's `sources`, and the consumer in the source's `consumers`. Each side also remembers
where the edge sits on the other (`sourceSlots`/`consumerSlots`), which is what lets an edge be
removed in constant time, without searching either array.

## Live and idle computeds

The `consumers` half of an edge only exists while the consumer is *live*: an effect (until it's
disposed), or a computed that something live consumes in turn. A computed nothing consumes is
*idle*: it still remembers its `sources`, but isn't in their `consumers`, so its sources hold no
reference to it (once the application drops it, it can be garbage collected) and a write doesn't
spend time marking it. The price is that nothing tells an idle computed when it's out of date; it
works that out for itself on its next read, by checking its sources (see `ensureFresh`).

A computed goes live when it gains its first consumer, linking itself into its own sources (which
may make *them* go live, and so on up), and idle again when it loses its last.
*/

/** What a cell stands for, which decides how it takes part in the graph. */
type kind =
  | Atom
  | Computed
  | Effect

/** One node of the dependency graph. */
type rec t = {
  id: int,
  kind: kind,
  /**
  Computed: `true` means a source *might* have changed and this cell must be checked (see
  `ensureFresh`) before its cached value can be trusted; only ever set while the cell is live.
  Effect: `true` means it's due -- a source might have changed since it last ran, and its `notify`
  has been (or, once the current write settles, will be) called; `EffectBase.run` clears it. Always
  `false` for an Atom.
  */
  mutable dirty: bool,
  /**
  The epoch at which this cell's value last *actually* changed -- for an Atom, whenever
  `Atom.set`/`update` writes a genuinely different value; for a Computed, whenever `recompute`
  produces one that isn't `equal` to what it had. Unused (stays `0`) for an Effect, which has no
  value.
  */
  mutable lastChangedEpoch: int,
  /**
  Computed: the epoch as of its last actual recompute (whether or not that recompute changed the
  value). Effect: the epoch as of the start of its last run. Either way, it's what `sourceChanged`
  compares a dependency's `lastChangedEpoch` against, to tell whether that reflects a change this
  cell has already accounted for. Starts at `-1` for a Computed, a value no real epoch ever takes,
  meaning "never computed yet". Unused (stays `0`) for an Atom.
  */
  mutable lastComputedEpoch: int,
  /**
  Computed only: the last epoch at which `ensureFresh` confirmed the cached value current. What an
  idle computed goes by instead of `dirty`: if no atom has been written since (the global epoch is
  still this one), nothing can have changed.
  */
  mutable verifiedEpoch: int,
  /**
  Whether `runTracked` is currently running this cell's computation/body. `Computed` uses it to
  report a computation that reads its own signal, rather than recursing forever.
  */
  mutable running: bool,
  /**
  The number of the `runTracked` call that last registered this cell as a source, so reading the
  same signal again in the same run is recognised without searching the consumer's `sources`.
  */
  mutable trackedInRun: int,
  /**
  The cells this one read from during its last run (Computed/Effect only), in the order it first
  read them. Updated on every run by `runTracked`, so a dependency that stops being read (e.g.
  behind a branch that took the other path) is pruned rather than lingering forever.
  */
  sources: array<t>,
  /**
  For each of `sources`, this cell's position in that source's `consumers`. Only kept while this
  cell is live.
  */
  sourceSlots: array<int>,
  /**
  The live cells that read this one during *their* last run (Atom/Computed only; always empty for
  an Effect, since nothing can depend on an effect).
  */
  consumers: array<t>,
  /** For each of `consumers`, this cell's position in that consumer's `sources`. */
  consumerSlots: array<int>,
  /** Recomputes the cell's value. Filled in by `Computed`; a no-op for other kinds. */
  mutable recompute: unit => unit,
  /**
  Tells the effect it has become due, so its scheduler can arrange for it to rerun. Called by
  `settle`, never directly. Filled in by `EffectBase`; a no-op for other kinds.
  */
  mutable notify: unit => unit,
  /** Whether this (Effect) cell has been disposed and must never run again. */
  mutable disposed: bool,
}

/** Creates a fresh, unconnected cell of the given kind, with a unique `id`. */
let make: kind => t

/**
The cell currently being computed/run, if any -- what `get()` calls register a dependency edge
against. A plain module-level ref rather than a stack: `runTracked` saves and restores it
recursively, which already gives the right nesting behavior for a computed reading another computed
reading an atom, etc.
*/
let activeConsumer: ref<option<t>>

/**
How many `Batch.run` calls are currently nested. Writes still take effect immediately (see
`Atom.set`); this only delays `settle` until the outermost batch exits, so effects triggered by
several writes in the same batch are notified once, after all of them have landed, instead of once
per write.
*/
let batchDepth: ref<int>

/**
Registers the given source as a dependency of the currently-active consumer, if there is one --
called by `Atom.get`/`Signal.get` after they've ensured their own value is fresh. A no-op outside
any tracked computation (a plain top-level read establishes no subscription), and for a source this
run has already registered.

A source read in the same position as in the consumer's previous run -- the usual case, where a
computation reads the same signals in the same order every time -- costs nothing beyond noticing
that: the existing edge is simply kept.
*/
let track: t => unit

/**
Runs the function with the given consumer installed as the active tracker, so any `Atom`/`Computed`
it reads (directly or through further `get()` calls) registers itself as one of `consumer.sources`
via `track`. Dependencies not read this time around are pruned: once the function returns, each of
the *previous* sources it didn't read again is dropped, and this consumer removed from that source's
`consumers`, so a dependency behind a branch that wasn't taken this run stops notifying it of future
changes. The previous active consumer is restored, and the pruning still done, even if the function
throws.
*/
let runTracked: (t, unit => 'a) => 'a

/**
Marks every live cell transitively reachable from the source's `consumers` as `dirty` -- meaning
"one of your dependencies changed; you must check before trusting your cached value" -- and queues
every reachable `Effect` to be notified by `settle`. Called exactly once, synchronously, whenever
the source's own value actually changed (from `Atom.set`/`update` for an atom; a `Computed`'s own
`recompute` never calls this, since the marking this does from the atom that started the update
already covers every live computed downstream of it). Idle computeds aren't reachable this way, and
aren't marked: see `ensureFresh`.

This deliberately does *not* try to tell whether a downstream cell will actually need to recompute
-- it can't know that without recomputing every intermediate `Computed` in between, which would
defeat the point of marking lazily at all. Instead it marks everything reachable `dirty` cheaply, up
front (skipping cells that are already dirty, whose own consumers were marked when they were), and
`ensureFresh` is what later decides -- once something actually reads a dirty cell -- whether a real
recompute is needed, by checking whether any dependency's value *actually* changed rather than just
being reachable from one that did.
*/
let markDirty: t => unit

/**
Brings a `Computed` cell up to date, recomputing only if it turns out to genuinely need to -- the
other half of the strategy `markDirty` documents. A no-op for an `Atom` (its value is always current
the moment `set` returns), and for a computed that can't be out of date: a live one that isn't
dirty, or an idle one already verified at the current epoch.

A dirty cell might have been marked so only because *something* upstream changed, not necessarily
any of the specific values this cell actually reads -- e.g. a diamond dependency graph where a
shared ancestor changed but the intermediate `Computed` this cell depends on recomputed to an equal
value. So rather than recomputing unconditionally, this asks `sourceChanged` -- the only way to
tell "did something I actually depend on change" from "was I merely reachable from a change"
without redoing the work. Only if that's true does `recompute` actually run; otherwise this cell's
cached value is still correct, and it's simply marked clean.

An idle computed is never marked dirty, so it goes through the same check whenever any atom at all
has been written since it was last verified (the global epoch has moved on from its
`verifiedEpoch`) -- and skips it, like a clean live one, when none has.

The never-computed-yet case (`lastComputedEpoch < 0`) always recomputes unconditionally: there's no
cached value yet to keep, and (before the first run) `sources` is empty besides, so the epoch check
would otherwise vacuously answer "nothing changed".
*/
let ensureFresh: t => unit

/**
Whether any of the given Computed/Effect cell's sources has actually changed since the cell last
computed/ran. Recursively ensures every source is itself fresh first (an `Atom` source is trivially
already current; an out-of-date `Computed` source resolves via `ensureFresh`), then checks whether its
`lastChangedEpoch` is *newer* than the cell's `lastComputedEpoch`, stopping at the first one that
is.
*/
let sourceChanged: t => bool

/**
Calls `notify` on every effect that has become due since the last call, in the order they became
due -- including ones that become due while this is running (e.g. a scheduler that reruns an effect
right away, whose body writes an atom): the pending queue is worked through front to back, so that
happens naturally, with no separate re-entrant drain. A no-op while a `Batch.run` is still open
(`batchDepth > 0`), in which case the batch itself calls this once when the outermost one exits; and
a no-op when called from inside a `notify` that this call is itself already running, for the same
reason (the outer drain picks the new work up).

Called after every atom write, so a `notify` only ever runs once the write (or batch of writes) that
made its effect due has fully landed, never part-way through `markDirty`. An effect is notified
once each time it goes from idle to due; further changes before it reruns don't notify it again.

If a `notify` throws, the rest are still notified; the first exception thrown is then rethrown to
whoever called this (any others are dropped).

Effects becoming due while this runs could go on forever -- an effect that writes a signal it reads,
rerun on the spot by its scheduler, and never settling. So this counts passes: the effects already
due when it starts are the first, the ones those make due the second, and so on. After 100 passes
it throws instead of continuing, leaving whatever is still due queued for the next call.
*/
let settle: unit => unit

/**
Removes the given (Effect) cell from every source's `consumers` list, so it stops being notified,
and forgets its sources. Used by `EffectBase.dispose`, after marking the cell `disposed`.
*/
let disconnect: t => unit
