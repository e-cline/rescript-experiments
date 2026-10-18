/***
A page: the HTML the first request for a route gets, with the payload in it, or the payload by
itself for a client asking for one (`navigate`, `refresh`, `useRefetchable`).

```rescript
@module("virtual:weft/assets") external assets: WeftServer.Page.assets = "default"

let notePage: Servy.Handler.t = async ctx =>
  WeftServer.Page.respond(ctx.request, <NotePage id />, ~assets, ~title="Note")
```

The HTML is one streamed response: the document's head (the bootstrap's script, `async` so it runs
as soon as it's loaded, and its preloads and stylesheets), `<div id="root">`, then each row of the
payload as an inline script as soon as the server writes it, until the payload ends. The bootstrap
(`Bootstrap`) reads the rows from those scripts, whether they ran before it loaded or after. When a
row refers to an entrypoint, a `modulepreload` link for its chunk goes before it, so the browser
starts loading it straight away.
*/

/** What a page loads the client with: `virtual:weft/assets`' default export. */
type assets = {
  /** Module scripts, in order (in development, Vite's client, then the bootstrap). */
  scripts: array<string>,
  /** The chunks the bootstrap imports. */
  preloads: array<string>,
  /** Stylesheets. */
  styles: array<string>,
  /** For each entrypoint file, by id: its chunk, then the chunks it imports. */
  entrypoints: dict<array<string>>,
}

/**
The HTML page for `element`, streamed as it renders. `title` and `head` (raw HTML, for anything else
the head needs) go in the head. `onError` and `signal` are `Render.toStream`'s.
*/
let toStream: (
  WeftCore.Element.t,
  ~assets: assets,
  ~title: string=?,
  ~head: string=?,
  ~onError: exn => option<string>=?,
  ~signal: Streams.Signal.t=?,
) => Streams.t

/**
How a page's inline script writes one row (or, with `None`, that the payload is complete): the
script itself, its argument escaped so that nothing in it can end the script.
*/
let rowScript: option<string> => string

/** Whether an `Accept` header asks for the bare payload (`Payload.contentType`). */
let wantsPayload: option<string> => bool

/**
The response to `request` for `element`: the bare payload if the request asks for it
(`wantsPayload`), and otherwise the HTML page (`toStream`). Either way it streams, and stops when
the request is aborted (the client went away). It varies by `Accept`, and says so.
*/
let respond: (
  Request.t,
  WeftCore.Element.t,
  ~assets: assets,
  ~title: string=?,
  ~head: string=?,
  ~onError: exn => option<string>=?,
) => Response.t
