---
'@e-cline/res_trees': minor
'@e-cline/res_signal_maps': patch
---

Rename `@e-cline/res_b_tree` to `@e-cline/res_trees`, since it holds three trees (`BTree`, `AvlTree`
and `ChunkTree`) rather than one. Its namespace is now `ResTrees` instead of `ResBTree`: replace
`ResBTree.BTree` with `ResTrees.BTree`, and the package name in your `package.json` and
`rescript.json` `dependencies`. The modules and their APIs are unchanged. `res_signal_maps` now
depends on `@e-cline/res_trees`.
