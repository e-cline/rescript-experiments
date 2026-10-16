/***
Backs `AtomMap.filterMap` / `ComputedMap.filterMap` (and, via a thin wrapper, `.filter`).

Like `MapValues` (and unlike `Rekey`), `filterMap` never changes a key's identity, so it can replay
diffs directly against the previous result tree -- no deferred-adds/collision handling needed. The
only extra bookkeeping versus `MapValues` is tracking whether a key was actually present in the
*filtered* output before, since an upstream `Different` change can turn into any of: an `OnlyRight`
(the entry newly passes the filter), an `OnlyLeft` (it newly fails the filter), a `Different` (it
passes both before and after), or nothing at all (it fails the filter both before and after).
*/

// See `AtomMap.res`'s own comment on these opens: `Signal`/`Computed` are
// res_signals', `BTree` is res_trees's, each reached through its own
// namespace.
open ResSignals
open ResTrees

let buildFromScratch = (
  ~id: Belt.Id.comparable<'k, 'id>,
  sourceTree: BTree.t<'k, 'v, 'id>,
  filterMapFn: ('k, 'v) => option<'r>,
): BTree.t<'k, 'r, 'id> => {
  let entries = []
  BTree.forEach(sourceTree, (key, value) =>
    switch filterMapFn(key, value) {
    | Some(result) => Array.push(entries, (key, result))
    | None => ()
    }
  )
  BTree.fromArray(~id, ~maxNodeSize=BTree.maxNodeSize(sourceTree), entries)
}

let build = (
  ~name: string,
  ~historyLength: int,
  ~id: Belt.Id.comparable<'k, 'id>,
  source: Signal.t<BTree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
  filterMapFn: ('k, 'v) => option<'r>,
): Signal.t<BTree.t<'k, 'r, 'id>, MapDiff.t<'k, 'r>> =>
  Computed.makeIncremental(
    ~name,
    ~historyLength,
    ~computeDiff=(prev, curr, _, _) => Some(MapDiff.ofTrees(prev, curr)),
    (previous, lastComputedEpoch) => {
      let sourceTree = Signal.get(source)
      let fromScratch = () => Computed.Value(buildFromScratch(~id, sourceTree, filterMapFn))
      switch previous {
      | None => fromScratch()
      | Some(previousTree) =>
        switch Signal.getDiffSince(source, lastComputedEpoch) {
        | Reset => fromScratch()
        | Diffs([]) => Computed.Value(previousTree)
        | Diffs(batches) =>
          let diff: MapDiff.t<'k, 'r> = []
          let tree = ref(previousTree)
          batches->Belt.Array.forEach(batch =>
            batch->Belt.Array.forEach(entry =>
              switch entry {
              | MapDiff.OnlyRight(key, value) =>
                // Added upstream: include it iff it passes the filter.
                switch filterMapFn(key, value) {
                | Some(result) =>
                  tree := BTree.set(tree.contents, key, result)
                  Array.push(diff, MapDiff.OnlyRight(key, result))
                | None => ()
                }
              | MapDiff.OnlyLeft(key, _) =>
                // Removed upstream. Only emit a diff entry (and delete) if it was
                // actually present in the filtered output -- it may have already
                // failed the filter.
                switch BTree.get(tree.contents, key) {
                | Some(oldValue) =>
                  tree := BTree.remove(tree.contents, key)
                  Array.push(diff, MapDiff.OnlyLeft(key, oldValue))
                | None => ()
                }
              | MapDiff.Different(key, _, rightValue) =>
                let hadOld = BTree.get(tree.contents, key)
                switch filterMapFn(key, rightValue) {
                | None =>
                  // Newly fails the filter (or still does): remove if it was there before.
                  switch hadOld {
                  | Some(oldValue) =>
                    tree := BTree.remove(tree.contents, key)
                    Array.push(diff, MapDiff.OnlyLeft(key, oldValue))
                  | None => ()
                  }
                | Some(result) =>
                  tree := BTree.set(tree.contents, key, result)
                  Array.push(
                    diff,
                    switch hadOld {
                    | Some(oldValue) => MapDiff.Different(key, oldValue, result)
                    | None => MapDiff.OnlyRight(key, result)
                    },
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
