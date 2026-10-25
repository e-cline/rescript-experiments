---
'@e-cline/weft_server': patch
---

RPC answers bring their stylesheets: `RpcServer.respond` takes `~assets` (`virtual:weft/assets`, as
`Page.respond` does), and an answer with elements in it sends the sheets of their classes, as a
page's payload does. The client's call resolves once they've loaded, so what it renders never shows
without its CSS. Without `~assets`, nothing changes. `Page.stylesOf` gives the stylesheets in an
app's assets, as `Render` takes them.
