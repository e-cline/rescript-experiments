/***
Backs `AtomMap.fold` / `ComputedMap.fold` (and the `count`/`sum` convenience wrappers built on
it), modeled on Jane Street's `Incr_map.unordered_fold`.

Unlike the derived-map operations (`MapValues`, `FilterMap`, `Rekey`), this doesn't produce a
`BTree.t` at all: there's no `MapDiff.t`, and (per `spec`'s own fields) no `historyLength`, since a
scalar `'acc` has no natural diff shape for a history buffer to hold. What's shared with the
derived-map operations is only the replay strategy: on the first computation, or whenever `source`'s
history can't cover the gap, `spec.add` is folded over every entry in `source`'s current tree from
scratch; otherwise each diff batch since last time is replayed into the previous accumulator via
`spec.add`/`spec.remove`/`spec.update`.
*/

// See `AtomMap.res`'s own comment on these opens: `Signal`/`Computed` are
// res_signals', `BTree` is res_b_tree's, each reached through its own
// namespace.
open ResSignals
open ResBTree

/**
How a map's entries are folded into an accumulator of type `'acc`: `init` is the accumulator for an
empty map, and `add`/`remove`/`update` fold one entry's arrival, departure or change into it.
*/
type spec<'k, 'v, 'acc> = {
  /** The accumulator for an empty map. */
  init: 'acc,
  /** Folds a newly-added entry into `acc`. */
  add: ('k, 'v, 'acc) => 'acc,
  /** Folds a removed entry out of `acc`. */
  remove: ('k, 'v, 'acc) => 'acc,
  /**
  Folds a changed entry's old value out and new value in, in one step. Defaults to
  `add(key, newValue, remove(key, oldValue, acc))` when `None`; supply this only when a same-key
  update can be folded more cheaply than a remove-then-add (e.g. `count`, where a value change never
  affects the count at all).
  */
  update: option<('k, 'v, 'v, 'acc) => 'acc>,
  /**
  When true, resets `acc` to `init` whenever the source map is empty after a batch, instead of
  trusting the accumulated `remove`s to have arrived back at it. Mainly useful for numeric folds
  like `sum`, where floating-point rounding error could otherwise drift across many add/remove
  cycles even though the true answer for an empty map is always exactly `init`.
  */
  revertToInitWhenEmpty: bool,
}

let build = (
  ~name: string,
  source: Signal.t<BTree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
  spec: spec<'k, 'v, 'acc>,
): Signal.t<'acc, unit> =>
  Computed.makeIncremental(~name, (previous, lastComputedEpoch) => {
    let sourceTree = Signal.get(source)
    let fromScratch = () =>
      BTree.reduce(sourceTree, spec.init, (acc, key, value) => spec.add(key, value, acc))
    let acc = switch previous {
    | None => fromScratch()
    | Some(previousAcc) =>
      switch Signal.getDiffSince(source, lastComputedEpoch) {
      | Reset => fromScratch()
      | Diffs(batches) =>
        batches->Belt.Array.reduce(previousAcc, (acc, batch) =>
          batch->Belt.Array.reduce(
            acc,
            (acc, entry) =>
              switch entry {
              | MapDiff.OnlyRight(key, value) => spec.add(key, value, acc)
              | MapDiff.OnlyLeft(key, value) => spec.remove(key, value, acc)
              | MapDiff.Different(key, leftValue, rightValue) =>
                switch spec.update {
                | Some(update) => update(key, leftValue, rightValue, acc)
                | None => spec.add(key, rightValue, spec.remove(key, leftValue, acc))
                }
              },
          )
        )
      }
    }
    let finalAcc = spec.revertToInitWhenEmpty && BTree.isEmpty(sourceTree) ? spec.init : acc
    Computed.Value(finalAcc)
  })
