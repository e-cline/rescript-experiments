---
'@e-cline/weft_server': patch
---

A payload response can be inspected in the browser's DevTools. It's now sent with
`cache-control: private, no-cache` (`Payload.cacheControl`) instead of `no-store`, which leaves
Chromium with no body to show for a streamed response (the request is listed as canceled). The
page's HTML keeps `no-store`.
