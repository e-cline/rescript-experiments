/***
HTML that is safe to send by construction. An `Html.t` can only be made from
text that has been escaped (`text`), from other `Html.t` values, or by
explicitly vouching for a string (`raw`), so a value from a request can't end
up in a page unescaped by accident.

The `html` tagged template builds markup around interpolated `Html.t` values:

```rescript
let greeting = name => Html.html`<p>Hello, ${Html.text(name)}!</p>`
```
*/

type t

/**
Escapes `&`, `<`, `>`, `"` and `'`, making a string safe in element content and
quoted attribute values.
*/
let escape: string => string

/**
Plain text, escaped. Safe between tags and inside a quoted attribute value.
It is not enough for a URL attribute or inside a `<script>`: use `url` and
`json` there.
*/
let text: string => t

/**
A URL for an attribute like `href` or `src`. Escaping alone doesn't make a URL
safe to link to: `javascript:alert(1)` has nothing in it to escape. This lets
through `http:`, `https:`, `mailto:` and `tel:` URLs and relative ones, and
turns anything else into `about:invalid`, which goes nowhere.

```rescript
Html.html`<a href="${Html.url(profile.website)}">${Html.text(profile.name)}</a>`
```
*/
let url: string => t

/**
JSON for inside a `<script>` element, where HTML escaping doesn't apply and
what has to be avoided is the text `</script>`. The characters that could end
the script are written as `\uXXXX` escapes, which mean the same to JSON.

```rescript
Html.html`<script type="application/json" id="data">${Html.json(data)}</script>`
```
*/
let json: JSON.t => t

/** Markup to include as it is. Only for strings you wrote or have already sanitized. */
let raw: string => t

let int: int => t

let empty: t

let join: (array<t>, ~separator: t=?) => t

/** The tag for a template literal of trusted markup with `Html.t` interpolations. */
let html: (array<string>, array<t>) => t

let toString: t => string
