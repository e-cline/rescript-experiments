---
'@e-cline/trees': minor
---

Add `SortedMap`, the interfaces the trees share, as module types: `SortedMap.Persistent` (`BTree`,
`AvlTree`, `ChunkTree`), `SortedMap.S` (`Persistent` with the `make`/`fromArray` that take only a
comparator: `AvlTree` and `ChunkTree`) and `SortedMap.Mutable` (every `Mutable` wrapper). Each
tree's `.resi` is now an `include` of one of these, so code that should work with any tree can take
one as a functor argument. The trees' APIs are unchanged, and `ChunkTree.S` is now an alias for
`SortedMap.S`. Each shared operation is documented once, in `SortedMap.res`, and what is particular
to a tree in its module comment.
