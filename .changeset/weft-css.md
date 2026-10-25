---
'@e-cline/weft_css': patch
---

A new package: styles declared in ReScript, extracted to CSS at build time. `Css.class`, `Css.var`,
`Css.keyframes` and `Css.global`, at a module's top level, take a typed record of properties (with
nested blocks, `selectors` and `media`); `ppx_weft` names each from its module and binding, and
`weft_vite_plugin` extracts each file's styles into a stylesheet of its own, leaving only the names
in the JavaScript. Classes are in the cascade layer `weft.components`, globals and variables in
`weft.base`. `Css.vars` sets variables in a `style` prop, for what changes at run time; `Css.cx`
joins class names. `Sheets.load` and `Sheets.isLoaded` load a stylesheet once per document, sharing
their state with the page's inline runtime.
