/***
`AvlTree` through the shared conformance suite: both a check on the suite itself (a tree known
to be right must pass it) and the reference point for `maxComparedAfter25Edits`.
*/

include Conformance.Make(
  AvlTree,
  {
    let name = "AvlTree (conformance)"
    let maxComparedAfter25Edits = 500
  },
)
