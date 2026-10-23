---
'@e-cline/weft': patch
'@e-cline/weft_dom': patch
---

`Hooks.useId()`: an ID unique on the page, for linking elements, the same in the server's HTML
(`WeftDom.Html`) as once hydrated, since both sides make it from the component's position in the
tree. A component mounted later on the client gets a fresh one. `Html.render(~idPrefix)` and
`Client.hydrateRoot(~idPrefix)` set what the IDs start with. `DomProps` gains `aria-describedby` and
`aria-labelledby`.
