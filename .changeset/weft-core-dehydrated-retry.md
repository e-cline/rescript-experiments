---
'@e-cline/weft': patch
---

Fixes a pending `Suspense` boundary rendered twice: when its content arrived after hydration had
started, and suspended as it hydrated (an entrypoint's chunk still loading, say), the boundary
rendered its content on the client after the server's, which stayed, unhydrated. It now stays as the
server sent it until what it waits on settles, then hydrates.
