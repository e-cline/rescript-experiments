/***
The diff type recorded by the signal backing `AtomMap`/`ComputedMap`: one entry per key that was
added, removed, or changed value between two consecutive snapshots of the map's tree, exactly as the
tree's `diff` (`Trees.SortedMap.Persistent.diff`) reports it. Naming mirrors `diff`'s own
callback names (`onlyLeft`/`onlyRight`/`different`) rather than a more map-flavored
"added"/"removed"/"changed", since "left"/"right" is what's meaningful when a derived map's diff
(e.g. `AtomMap.mapValues`'s result) is itself diffed against a *different* pair of trees than the
ones a reader might assume.
*/

/**
One key's change between an older tree (left) and a newer one (right): `OnlyLeft(key, value)` if
it's only in the older tree (it was removed), `OnlyRight(key, value)` if only in the newer one (it
was added), or `Different(key, leftValue, rightValue)` if it's in both with unequal values.
*/
type entry<'k, 'v> =
  | OnlyLeft('k, 'v)
  | OnlyRight('k, 'v)
  | Different('k, 'v, 'v)

/** The changes between two snapshots of a map: one `entry` per affected key. */
type t<'k, 'v> = array<entry<'k, 'v>>

/** `ofTrees` for any persistent tree. */
module Make = (Tree: Trees.SortedMap.Persistent) => {
  /**
  The diff between `left` and `right`, via `Tree.diff` -- cheap for two trees that share structure
  (see `Trees.SortedMap.Persistent.diff`).
  */
  let ofTrees = (
    ~valueEqual: option<('v, 'v) => bool>=?,
    left: Tree.t<'k, 'v, 'id>,
    right: Tree.t<'k, 'v, 'id>,
  ): t<'k, 'v> => {
    let entries = []
    Tree.diff(
      left,
      right,
      ~valueEqual?,
      ~onlyLeft=(key, value) => Array.push(entries, OnlyLeft(key, value)),
      ~onlyRight=(key, value) => Array.push(entries, OnlyRight(key, value)),
      ~different=(key, leftValue, rightValue) =>
        Array.push(entries, Different(key, leftValue, rightValue)),
    )
    entries
  }
}

/** The diff between two `Trees.BTree.t`s, the trees `AtomMap`/`ComputedMap` hold. */
include Make(Trees.BTree)

/**
Default `historyLength` for the signal backing `AtomMap`/`ComputedMap`: enough slack for a chained
derived-map operation (`mapValues`, `filterMap`, ...) to update incrementally across several batched
writes before falling back to a full rebuild. Pass `~historyLength=0` to opt out of diffing
entirely.
*/
let defaultHistoryLength = 64
