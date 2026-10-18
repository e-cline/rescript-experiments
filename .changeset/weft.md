---
'@e-cline/weft': patch
---

New package: `Weft`, the public API of `@e-cline/weft_core` and `@e-cline/weft_dom` in one module.
`Weft.Hooks`, `Context`, `Memo`, `Transition`, `ErrorBoundary`, `Suspense`, `Jsx`, `Portal`,
`Client` and `Dom` are aliases of the originals, so they add nothing to a bundle, and the
renderer-writing and testing modules stay in `weft_core`.
