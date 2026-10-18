/***
Backs `AtomMap.map` / `ComputedMap.map`, modeled on Jane Street's `Incr_map.rekey`.

Unlike `MapValues`/`FilterMap`, `map` can change a key's identity (or, if
`mapFn` isn't careful, map several source keys onto the same output key),
so it can't just replay diffs in place. Instead: within each batch of
upstream changes, every removal -- and the "old side" of an entry whose
output key changed -- is applied immediately, but every addition -- both
a genuine new entry and the "new side" of a moved one -- is deferred into
a list and only applied once every removal in that batch has landed. That
ordering means a key freed up by one entry's removal is safely available
to another entry's addition within the same batch (including a
same-batch "swap" of two entries' output keys), while a genuine collision
between two still-live entries is reliably caught (via the tree's `has` on
each deferred add) rather than one silently overwriting the other.

One deliberate simplification: a same-key value change
(`MapDiff.Different` where `mapFn` happens to produce the same output key
for both the old and new value) is always handled as a plain
remove-then-deferred-add, like a genuine move, rather than detecting that
special case and updating in place. The result is identical either way;
the only difference is that the emitted diff for that change is an
`OnlyLeft`/`OnlyRight` pair instead of a single `Different` -- a
reasonable trade against the extra machinery (unpacking `id`'s
comparator, see `Trees.BTree.make`'s comment) that
detecting it directly would need.

Multiple batches (i.e. several upstream updates made without an
intervening read) are applied one at a time, in order -- each batch's
removals and additions are fully committed before the next batch is
processed -- so a key that moves more than once across separate batches
is tracked correctly throughout.

"Batch" here means one `Atom.set`/`update` call's diff (what
`Signal.getDiffSince` hands back one array element per) -- not a
`Batch.run` call. `Batch.run` only defers notifying *effects*; each write
inside it still advances the epoch and records its own diff separately,
so swapping two entries' output keys via two separate `AtomMap.setValue`
calls (even inside one `Batch.run`) is *two* batches here, each seeing
the other's key as still occupied -- a spurious collision. To swap
atomically, make one source write whose diff already contains both
`Different` entries together (e.g. one `AtomMap.update` building the
whole new tree at once).
*/

// `Signal`/`Computed` are signals', reached through its namespace (see
// `AtomMap.res`'s own comment on this).
open Signals

/** The operation for maps built on `Tree`. */
module Make = (Tree: MapTree.S) => {
  module Diff = MapDiff.Make(Tree)

  let buildFromScratch = (
    ~name: string,
    ~id: Belt.Id.comparable<'k2, 'id2>,
    sourceTree: Tree.t<'k, 'v, 'id>,
    mapFn: ('k, 'v) => ('k2, 'v2),
  ): Tree.t<'k2, 'v2, 'id2> => {
    let result = ref(Tree.emptyLike(sourceTree, ~id))
    Tree.forEach(sourceTree, (key, value) => {
      let (key2, value2) = mapFn(key, value)
      if Tree.has(result.contents, key2) {
        JsError.throwWithMessage(
          `${name}: mapFn produced the same output key for two different input entries.`,
        )
      }
      result := Tree.set(result.contents, key2, value2)
    })
    result.contents
  }

  let build = (
    ~name: string,
    ~historyLength: int,
    ~id: Belt.Id.comparable<'k2, 'id2>,
    source: Signal.t<Tree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
    mapFn: ('k, 'v) => ('k2, 'v2),
  ): Signal.t<Tree.t<'k2, 'v2, 'id2>, MapDiff.t<'k2, 'v2>> =>
    Computed.makeIncremental(
      ~name,
      ~historyLength,
      ~computeDiff=(prev, curr, _, _) => Some(Diff.ofTrees(prev, curr)),
      (previous, lastComputedEpoch) => {
        let sourceTree = Signal.get(source)
        let fromScratch = () => Computed.Value(buildFromScratch(~name, ~id, sourceTree, mapFn))
        switch previous {
        | None => fromScratch()
        | Some(previousTree) =>
          switch Signal.getDiffSince(source, lastComputedEpoch) {
          | Reset => fromScratch()
          | Diffs([]) => Computed.Value(previousTree)
          | Diffs(batches) =>
            let diff: MapDiff.t<'k2, 'v2> = []
            let tree = ref(previousTree)
            let removeIfPresent = key2 =>
              switch Tree.get(tree.contents, key2) {
              | Some(oldValue) =>
                tree := Tree.remove(tree.contents, key2)
                Array.push(diff, MapDiff.OnlyLeft(key2, oldValue))
              | None => ()
              }
            batches->Belt.Array.forEach(batch => {
              // Additions in this batch (genuine new entries, and the "new side" of a
              // moved entry) are deferred until every removal below has landed -- see
              // the module comment above.
              let pendingAdds: array<('k2, 'v2)> = []
              batch->Belt.Array.forEach(entry =>
                switch entry {
                | MapDiff.OnlyRight(key, value) => Array.push(pendingAdds, mapFn(key, value))
                | MapDiff.OnlyLeft(key, value) =>
                  let (oldKey, _) = mapFn(key, value)
                  removeIfPresent(oldKey)
                | MapDiff.Different(key, leftValue, rightValue) =>
                  let (oldKey, _) = mapFn(key, leftValue)
                  removeIfPresent(oldKey)
                  Array.push(pendingAdds, mapFn(key, rightValue))
                }
              )
              pendingAdds->Belt.Array.forEach(((key2, value2)) => {
                if Tree.has(tree.contents, key2) {
                  JsError.throwWithMessage(
                    `${name}: mapFn produced the same output key for two different input entries.`,
                  )
                }
                tree := Tree.set(tree.contents, key2, value2)
                Array.push(diff, MapDiff.OnlyRight(key2, value2))
              })
            })
            Computed.ValueWithDiff(tree.contents, diff)
          }
        }
      },
    )
}
