---
'@e-cline/weft_dom': patch
'@e-cline/weft_server': patch
---

Events from before hydration are replayed: `WeftDom.Html.eventRuntime` (which `WeftServer.Page`
writes in the head of a page with HTML) records the clicks, submits, inputs and changes on elements
that haven't hydrated yet, and `Client.hydrateRoot` replays them, in order, through the elements'
own listeners once they have.
