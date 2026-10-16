/***
Backs `AtomMap.mapValues` / `ComputedMap.mapValues`. On the first computation, or whenever `source`'s history can't cover the gap since
this was last computed (`Signal.Reset`), maps every entry in `source`'s current tree from scratch.
Otherwise, replays the batches of `MapDiff.entry` changes `source` reports since the last
computation directly against the previous result tree -- touching only the keys that actually
changed -- producing this map's own `MapDiff.t` for further downstream consumers (e.g. a chained
`mapValues`) as a side effect of doing so, instead of re-diffing the two whole trees afterward.
*/

// `Signal`/`Computed` are res_signals', reached through its namespace (see
// `AtomMap.res`'s own comment on this).
open ResSignals

/** The operation for maps built on `Tree`. */
module Make = (Tree: MapTree.S) => {
  module Diff = MapDiff.Make(Tree)

  let buildFromScratch = (
    ~id: Belt.Id.comparable<'k, 'id>,
    sourceTree: Tree.t<'k, 'v, 'id>,
    mapFn: ('k, 'v) => 'r,
  ): Tree.t<'k, 'r, 'id> => {
    let entries = []
    Tree.forEach(sourceTree, (key, value) => Array.push(entries, (key, mapFn(key, value))))
    Tree.fromArrayLike(sourceTree, ~id, entries)
  }

  let build = (
    ~name: string,
    ~historyLength: int,
    ~id: Belt.Id.comparable<'k, 'id>,
    source: Signal.t<Tree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
    mapFn: ('k, 'v) => 'r,
  ): Signal.t<Tree.t<'k, 'r, 'id>, MapDiff.t<'k, 'r>> =>
    Computed.makeIncremental(
      ~name,
      ~historyLength,
      ~computeDiff=(prev, curr, _, _) => Some(Diff.ofTrees(prev, curr)),
      (previous, lastComputedEpoch) => {
        let sourceTree = Signal.get(source)
        let fromScratch = () => Computed.Value(buildFromScratch(~id, sourceTree, mapFn))
        switch previous {
        | None => fromScratch()
        | Some(previousTree) =>
          switch Signal.getDiffSince(source, lastComputedEpoch) {
          | Reset => fromScratch()
          | Diffs([]) =>
            // Nothing changed upstream; returning the same reference is
            // treated as a no-op (no new state, no diff recorded).
            Computed.Value(previousTree)
          | Diffs(batches) =>
            let diff: MapDiff.t<'k, 'r> = []
            let tree = ref(previousTree)
            batches->Belt.Array.forEach(batch =>
              batch->Belt.Array.forEach(entry =>
                switch entry {
                | MapDiff.OnlyRight(key, value) =>
                  let newValue = mapFn(key, value)
                  tree := Tree.set(tree.contents, key, newValue)
                  Array.push(diff, MapDiff.OnlyRight(key, newValue))
                | MapDiff.OnlyLeft(key, _) =>
                  // Read the outgoing mapped value from `tree` (which reflects every
                  // entry applied so far this round), not `previousTree` -- if this
                  // key was already touched earlier in the same batch (e.g. added,
                  // then later removed), `previousTree` wouldn't have it yet.
                  switch Tree.get(tree.contents, key) {
                  | Some(oldValue) =>
                    tree := Tree.remove(tree.contents, key)
                    Array.push(diff, MapDiff.OnlyLeft(key, oldValue))
                  | None =>
                    JsError.throwWithMessage(
                      `${name}: key removed upstream but missing from the mapped tree (unreachable)`,
                    )
                  }
                | MapDiff.Different(key, _, rightValue) =>
                  // Only the new value needs re-mapping; the old mapped value is read
                  // back rather than recomputed from the source's old value.
                  switch Tree.get(tree.contents, key) {
                  | Some(oldValue) =>
                    let newValue = mapFn(key, rightValue)
                    tree := Tree.set(tree.contents, key, newValue)
                    Array.push(diff, MapDiff.Different(key, oldValue, newValue))
                  | None =>
                    JsError.throwWithMessage(
                      `${name}: key changed upstream but missing from the mapped tree (unreachable)`,
                    )
                  }
                }
              )
            )
            Computed.ValueWithDiff(tree.contents, diff)
          }
        }
      },
    )
}
