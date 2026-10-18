/***
Backs `AtomMap.filterMap` / `ComputedMap.filterMap` (and, via a thin wrapper, `.filter`).

Like `MapValues` (and unlike `Rekey`), `filterMap` never changes a key's identity, so it can replay
diffs directly against the previous result tree -- no deferred-adds/collision handling needed. The
only extra bookkeeping versus `MapValues` is tracking whether a key was actually present in the
*filtered* output before, since an upstream `Different` change can turn into any of: an `OnlyRight`
(the entry newly passes the filter), an `OnlyLeft` (it newly fails the filter), a `Different` (it
passes both before and after), or nothing at all (it fails the filter both before and after).
*/

// `Signal`/`Computed` are signals', reached through its namespace (see
// `AtomMap.res`'s own comment on this).
open Signals

/** The operation for maps built on `Tree`. */
module Make = (Tree: MapTree.S) => {
  module Diff = MapDiff.Make(Tree)

  let buildFromScratch = (
    ~id: Belt.Id.comparable<'k, 'id>,
    sourceTree: Tree.t<'k, 'v, 'id>,
    filterMapFn: ('k, 'v) => option<'r>,
  ): Tree.t<'k, 'r, 'id> => {
    let entries = []
    Tree.forEach(sourceTree, (key, value) =>
      switch filterMapFn(key, value) {
      | Some(result) => Array.push(entries, (key, result))
      | None => ()
      }
    )
    Tree.fromArrayLike(sourceTree, ~id, entries)
  }

  let build = (
    ~name: string,
    ~historyLength: int,
    ~id: Belt.Id.comparable<'k, 'id>,
    source: Signal.t<Tree.t<'k, 'v, 'id>, MapDiff.t<'k, 'v>>,
    filterMapFn: ('k, 'v) => option<'r>,
  ): Signal.t<Tree.t<'k, 'r, 'id>, MapDiff.t<'k, 'r>> =>
    Computed.makeIncremental(
      ~name,
      ~historyLength,
      ~computeDiff=(prev, curr, _, _) => Some(Diff.ofTrees(prev, curr)),
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
                    tree := Tree.set(tree.contents, key, result)
                    Array.push(diff, MapDiff.OnlyRight(key, result))
                  | None => ()
                  }
                | MapDiff.OnlyLeft(key, _) =>
                  // Removed upstream. Only emit a diff entry (and delete) if it was
                  // actually present in the filtered output -- it may have already
                  // failed the filter.
                  switch Tree.get(tree.contents, key) {
                  | Some(oldValue) =>
                    tree := Tree.remove(tree.contents, key)
                    Array.push(diff, MapDiff.OnlyLeft(key, oldValue))
                  | None => ()
                  }
                | MapDiff.Different(key, _, rightValue) =>
                  let hadOld = Tree.get(tree.contents, key)
                  switch filterMapFn(key, rightValue) {
                  | None =>
                    // Newly fails the filter (or still does): remove if it was there before.
                    switch hadOld {
                    | Some(oldValue) =>
                      tree := Tree.remove(tree.contents, key)
                      Array.push(diff, MapDiff.OnlyLeft(key, oldValue))
                    | None => ()
                    }
                  | Some(result) =>
                    tree := Tree.set(tree.contents, key, result)
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
}
