---
'@e-cline/weft_server': patch
---

Fixes:

- The payload decoder keeps a `__proto__` key in sent data as a field, rather than making it the
  decoded object's prototype.
- An error straight inside a `Suspense` (an entrypoint's prop that can't be sent, with no server
  component between) is that boundary's error, rather than failing the whole payload.
- `Navigation.make` takes `~onFailed`, called when `navigate` or `load` can't show a page (instead
  of rejecting). The bootstrap's loads the page the ordinary way. `refresh` still rejects.
- `Navigation.followLink` (and `staysInPage`), for a link's `onClick`: it navigates in place only
  for a plain click on a link to this origin, leaving clicks that open a new tab or window,
  downloads, `target`s and links within the page to the browser.
