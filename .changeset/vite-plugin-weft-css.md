---
'@e-cline/weft_vite_plugin': patch
---

`weft_css` styles: the plugin extracts each style file's stylesheet (running it in a module runner
of its own), strips the definitions from every bundle, and serves each sheet as a CSS module.
`weft()` puts the sheets in `virtual:weft/assets` for `weft_server`; `weftCss()` is the plugin for
an app without a server, whose modules import their sheets. In development an edit to a style
changes the stylesheet in place, with no reload. The test harness applies the head's stylesheets,
loads the others a task later (`holdStylesheets`, `releaseStylesheets`), reports what shows without
its CSS (`unstyled`), and names elements by `data-id` when they have no id.
