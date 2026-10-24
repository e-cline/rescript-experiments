---
'@e-cline/weft_server': patch
---

A navigation the server redirects lands where the redirect led. `Decoder.fetch` now resolves with
`Decoder.fetched` (the payload's `stream`, and the `url` a redirect led to, if one did) instead of
the bare stream; `webFetch` reports where the browser's `fetch` ended up. `Navigation.url` is that
URL, `navigate` calls `onNavigate` with it (so the browser's history gets it, not the URL asked
for), and a `load` or `refresh` that was redirected calls the new `~onRedirect` with it (the
browser's replaces the history's entry). `Decoder.Latest.fetchElement` resolves with the element and
its URL (`Decoder.Latest.fetched`).
