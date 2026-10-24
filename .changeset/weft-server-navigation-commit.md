---
'@e-cline/weft_server': patch
---

- `Navigation.navigate`, `load` and `refresh` resolve once the new page is on screen (its transition
  has committed), as documented, rather than as soon as it starts rendering: code awaiting them (to
  clear a pending state, say) no longer runs while the old page is still showing.
- `Bootstrap.start` takes a `~signal`: aborting it stops the page (its root unmounted, the history
  no longer followed), for tests that open one page after another in a document.
