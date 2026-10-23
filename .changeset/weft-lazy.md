---
'@e-cline/weft': patch
---

`Lazy.fromPromise`: an element that isn't ready yet. It suspends until its promise settles, then
renders what it resolved to in its place, with no fiber of its own, so a lazy element and the
element it resolved to can replace each other without remounting anything.

For server renderers: `ServerRender.run` calls a component outside the reconciler (stateful hooks
then fail with error 14, while `Hooks.use` still suspends), and `Entrypoint.mark`/`idOf` mark a
component as an entrypoint.
