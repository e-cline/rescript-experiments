---
'@e-cline/weft_dom': patch
'@e-cline/weft_core': patch
---

`WeftDom.Html`, the HTML renderer: renders an element tree to HTML on the server as the client would
render it, streaming each `Suspense` boundary's content once it's ready (with an inline runtime that
swaps it in), for the client to hydrate. `DomProps` now holds the prop rules both `DomHost` and
`Html` follow. `weft_core` gains `ServerRender.providedContext`, what a provider element provides,
for server renderers.
