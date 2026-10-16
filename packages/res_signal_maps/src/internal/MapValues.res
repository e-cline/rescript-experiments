/***
Backs `AtomMap.mapValues` / `ComputedMap.mapValues`. On the first computation, or whenever `source`'s history can't cover the gap since
this was last computed (`Signal.Reset`), maps every entry in `source`'s current tree from scratch.
Otherwise, replays the batches of `MapDiff.entry` changes `source` reports since the last
computation directly against the previous result tree -- touching only the keys that actually
changed -- producing this map's own `MapDiff.t` for further downstream consumers (e.g. a chained
`mapValues`) as a side effect of doing so, instead of re-diffing the two whole trees afterward.
*/

// See `AtomMap.res`'s own comment on these opens: `Signal`/`Computed` are
// res_signals', `BTree` is res_b_tree's, each reached through its own
// namespace.
open ResSignals
open ResBTree

let buildFromScratch = (
  ~id: Belt.Id.comparable<'k, 'id>,
  sourceTree: BTree.t<'k, 'v, 'id>,
  mapFn: ('k, 'v) => 'r,
): BTree.t<'k, 'r, 'id> => {
  let entries = []
  BTree.forEach(sourceTree, (key, value) => Array.push(entries, (key, mapFn(key, value))))
  BTree.fromArray(~id, ~maxNodeSize=BTree.maxNodeSize(sourceTree), entries)
}

let build = (
  ~name: string,
  ~historyLength: int,
  ~id: Belt.Id.comparable<'k, 'id>,
  source: Signal.t<BTree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
  mapFn: ('k, 'v) => 'r,
): Signal.t<BTree.t<'k, 'r, 'id>, MapDiff.t<'k, 'r>> =>
  Computed.makeIncremental(
    ~name,
    ~historyLength,
    ~computeDiff=(prev, curr, _, _) => Some(MapDiff.ofTrees(prev, curr)),
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
                tree := BTree.set(tree.contents, key, newValue)
                Array.push(diff, MapDiff.OnlyRight(key, newValue))
              | MapDiff.OnlyLeft(key, _) =>
                // Read the outgoing mapped value from `tree` (which reflects every
                // entry applied so far this round), not `previousTree` -- if this
                // key was already touched earlier in the same batch (e.g. added,
                // then later removed), `previousTree` wouldn't have it yet.
                switch BTree.get(tree.contents, key) {
                | Some(oldValue) =>
                  tree := BTree.remove(tree.contents, key)
                  Array.push(diff, MapDiff.OnlyLeft(key, oldValue))
                | None =>
                  JsError.throwWithMessage(
                    `${name}: key removed upstream but missing from the mapped tree (unreachable)`,
                  )
                }
              | MapDiff.Different(key, _, rightValue) =>
                // Only the new value needs re-mapping; the old mapped value is read
                // back rather than recomputed from the source's old value.
                switch BTree.get(tree.contents, key) {
                | Some(oldValue) =>
                  let newValue = mapFn(key, rightValue)
                  tree := BTree.set(tree.contents, key, newValue)
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
