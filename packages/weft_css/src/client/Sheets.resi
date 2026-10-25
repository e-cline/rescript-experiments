/***
Stylesheets in the browser: each loaded once per document, by URL, as a `<link rel="stylesheet">`
in the head. A link already in the document (the server's, in the first page's head) is adopted,
not added again, and one that loaded before anyone asked is known to have (its `sheet` is set).

```rescript
await WeftCss.Sheets.load("/assets/wk3f9a2-1c2d.css")
// the sheet applies: what needs it can show
```

A sheet that fails to load counts as loaded: what waits for it shows, unstyled, rather than never.
Without a document (on the server), every sheet is loaded already: there's nothing to wait for.

What's loaded is kept on `globalThis.__weftCss` (URL to state), so every copy of this module, and the
page's inline runtime, share it.
*/

/** Loads the stylesheet at `href`, unless it is or has been; resolves once it has loaded (or failed). */
let load: string => promise<unit>

/** Whether the stylesheet at `href` has loaded (or failed), so nothing need wait for it. */
let isLoaded: string => bool
