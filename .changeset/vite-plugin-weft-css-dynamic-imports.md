---
'@e-cline/weft_vite_plugin': patch
---

In a `weft()` app, an `import()` of one of the app's modules resolves once the stylesheets of what
it loads have loaded too: those of every style file it imports, and the sheets they depend on. So
code loaded lazily (a `Weft.Lazy` around an `import()`) renders styled, as entrypoints already did.
