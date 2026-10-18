---
'@e-cline/vite_plugin_weft': patch
---

New package: the Vite plugin for Weft's server components. It runs the server entry in an `rsc`
environment and makes every entrypoint file a chunk of its own on the client, refuses client imports
of server files (naming the chain of imports), fails on an RPC ID declared twice, serves the app in
development (refetching the page when a server file changes), and builds both, with `serve` to run
the build on Node. Its default bootstrap starts `WeftServer.Bootstrap`.
`@e-cline/vite_plugin_weft/testing` (with ReScript bindings, `WeftTesting`) runs an app's server in
a worker thread and its pages in the test's DOM, and can rewrite requests on their way to the server
(`rewriteBodies`).
