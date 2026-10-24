---
'@e-cline/weft_signals': patch
---

The hooks work in an entrypoint rendered on the server (to HTML): they give the signal's value
there, where they failed before (`useSyncExternalStore` without a server snapshot, error 15), and
the page fell back to rendering on the client.
