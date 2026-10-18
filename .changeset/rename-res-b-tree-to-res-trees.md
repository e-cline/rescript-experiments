---
'@e-cline/trees': minor
'@e-cline/signal_maps': patch
---

Rename `@e-cline/b_tree` to `@e-cline/trees`, since it holds three trees (`BTree`, `AvlTree` and
`ChunkTree`) rather than one. Its namespace is now `Trees` instead of `ResBTree`: replace
`ResBTree.BTree` with `Trees.BTree`, and the package name in your `package.json` and `rescript.json`
`dependencies`. The modules and their APIs are unchanged. `signal_maps` now depends on
`@e-cline/trees`.
