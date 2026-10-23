---
'@e-cline/weft_server': patch
'@e-cline/vite_plugin_weft': patch
---

Pages are rendered on the server: `Page.respond` streams the page as HTML (shell first, then each
`Suspense` boundary's content), from the payload decoded on the server as the browser will, with the
rows after the shell; and `Bootstrap` hydrates it. A shell that fails falls back to the rows alone.
`~html=false` opts a route out. `Navigation.makeForServer` is the page entrypoints read while the
HTML renders (it refuses to fetch), and `Navigation.wrap` is the tree to hydrate with. The plugin
adds `virtual:weft/ssr-references`, and `virtual:weft/assets` exports the server's `loadModule`.
