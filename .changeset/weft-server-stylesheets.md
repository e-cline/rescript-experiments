---
'@e-cline/weft_server': patch
---

Stylesheets: given the app's (`Page.assets`' `sheets` and `entrypointSheets`, from
`virtual:weft/assets`), `Render.toStream ~styles` sends each row the stylesheets its class names
need (`C` rows, before the row), and the decoder waits for them before a row's content shows
(`Decoder.make ~loadSheet`). A first page links the shell's stylesheets at the end of its head, held
until the shell is ready, preloads the ones the rest of the page needs, and each streamed segment
waits for its own before it's swapped in. Navigations and refetches keep the old content until the
new one's stylesheets have loaded.
