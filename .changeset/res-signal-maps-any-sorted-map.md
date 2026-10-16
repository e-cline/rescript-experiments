---
'@e-cline/res_signal_maps': minor
---

Support any `res_trees` sorted map, not only `BTree`: `SignalMap.Make(ResTrees.ChunkTree)` (or any
`ResTrees.SortedMap.S`, such as `AvlTree`) gives an `AtomMap` and a `ComputedMap` over that tree.
`AtomMap` and `ComputedMap` themselves are unchanged and still hold a `BTree.t`; their interfaces
are now `SignalMap.AtomMap` and `SignalMap.ComputedMap`, where each operation is documented, and
each gains a `tree` type naming the tree it holds. `MapDiff.Make` gives `ofTrees` for any tree, and
`MapTree` is the tree interface the maps are built on. The `internal/` algorithms (`MapValues`,
`FilterMap`, `Rekey`, `Fold`) are now functors over the tree. `AtomMap.setValue`'s comment now says
that setting a key to the value it already holds is a no-op, which it always was.
