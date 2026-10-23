---
'@e-cline/weft_dom': patch
'@e-cline/weft': patch
---

`WeftDom.Html`, the HTML renderer: renders an element tree to HTML on the server as the client would
render it, streaming each `Suspense` boundary's content once it's ready (with an inline runtime that
swaps it in), and `Client.hydrateRoot`, which hydrates it: the server's nodes adopted, handlers
attached, what the user typed kept, boundaries hydrating as their content arrives. `DomProps` now
holds the prop rules both `DomHost` and `Html` follow. `weft` gains `ServerRender.providedContext`,
what a provider element provides, for server renderers.
