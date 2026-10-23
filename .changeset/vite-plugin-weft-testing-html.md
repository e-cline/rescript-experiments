---
'@e-cline/weft_vite_plugin': patch
'@e-cline/weft_server': patch
---

The harness opens pages as the browser would: the page's HTML is applied as it's delivered (the
shell into the container, then each inline script and segment, in order), and the bootstrap hydrates
it once the shell is in. `WeftTesting.hydrated` waits for that, `htmlNodes` is what the HTML made
(for `removedSince`), `warnings` collects hydration's warnings, and `~bootstrap=false` (with
`startBootstrap`) opens a page as if the bootstrap's chunk hadn't loaded. `Bootstrap.main`, run
before the parser has reached `#root` (its script is `async`), now starts once it has.
