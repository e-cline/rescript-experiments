/***
The HTML renderer: an element tree to HTML, on the server, streamed. Server only (an app's client
build refuses this module).

```rescript
let html = WeftDom.Html.render(<App />)
let shell = await html->WeftDom.Html.shell // everything outside pending `Suspense` boundaries
// then `WeftDom.Html.rest(html)`: each boundary's content, as it's ready
```

Every kind of element is rendered as the client would render it, so the client can hydrate it:

- Host elements as tags, with their props as attributes by `DomProps`' rules (event handlers and
  `ref` left out); `style` as a `style` attribute; `value` and `checked` as the attributes that give
  the same initial state (a `textarea`'s text, `selected` on a `select`'s option).
- Text escaped, with `<!-- -->` between two texts in a row (which the parser would merge).
- Components called through `WeftCore.ServerRender.renderComponent`, so their hooks give their
  initial state; providers' values reach them.
- A component that suspends (`Hooks.use` on a pending promise), or a `Lazy` element that hasn't
  resolved, is waited for and rendered again, outside every `Suspense` boundary. Under one, the
  boundary's fallback is written in its place, with markers, and its content follows in a segment
  of its own, which an inline script swaps in.
- `ErrorBoundary`s don't catch on the server: an error goes to the nearest `Suspense` boundary,
  which is left for the client to render (a failed boundary), or fails the shell.
- Portals render nothing (their container isn't in the page).

A development build warns about nesting the HTML parser would repair (a `<div>` in a `<p>`, a `<tr>`
straight in a `<table>`), which would keep the page from hydrating as rendered.

The markers, comments the client's hydration reads:

```html
<!--$-->content<!--/$-->                                         content in place
<!--$?--><template id="wb:3"></template>fallback<!--/$-->        pending: its content is coming
<!--$!--><template data-digest="…"></template>fallback<!--/$-->  failed on the server
```

and a pending boundary's segment, once its content is ready:

```html
<template id="ws:3">content</template><script>$weftSwap(3)</script>
```
*/

/** A `ReadableStream` of bytes. */
type stream

/** An `AbortSignal`. */
type signal

/** An element being rendered to HTML. */
type t

/**
Starts rendering `element`. `onError` (by default, logging with `Console.error`) is called with each
error: one that fails a boundary, or the shell. It returns the digest to write with a boundary's,
if any; the message is written in development builds only. Aborting `signal` stops whatever is
pending.
*/
let render: (WeftCore.Element.t, ~onError: exn => option<string>=?, ~signal: signal=?) => t

/**
The shell: everything outside `Suspense` boundaries that are still pending, once all of it is
ready. Rejects with the error, if one is thrown outside every boundary.
*/
let shell: t => promise<string>

/**
What follows the shell: each pending boundary's segment (or the script failing it) as it's ready,
the inline runtime that swaps them in before the first. Ends once every boundary is done.
*/
let rest: t => stream

/** The shell, then the rest, as one stream. Errors if the shell fails. */
let renderToStream: (
  WeftCore.Element.t,
  ~onError: exn => option<string>=?,
  ~signal: signal=?,
) => stream

/**
All of `element`'s HTML, once everything has rendered: no boundary is left pending (each waits for
its content), though a failed one is still written as failed. For tests, and static pages.
*/
let renderToString: (WeftCore.Element.t, ~onError: exn => option<string>=?) => promise<string>

/** The inline runtime's source (`$weftSwap`, `$weftFail`), written once before the first segment. */
let runtime: string
