---
'@e-cline/weft_server': patch
'@e-cline/weft_core': patch
---

New package: `weft_server`, server components for Weft. `Render.toStream` renders a tree, server
components and all, into a streamed payload; `Client` decodes it into elements as it arrives,
loading entrypoints on demand, so a refetched payload patches the screen in place. `Testing`
connects the two in one process, for tests.

`weft_core`: `Deferred`, a promise whose outcome `Hooks.use` and `Lazy` elements can read the moment
it's settled; `ServerRender.suspendedOn`; and a rejected `Lazy` element now throws from its own
position, so an `ErrorBoundary` whose child it is catches it.
