/***
A page: the HTML the first request for a route gets, with the payload in it, or the payload by
itself for a client asking for one (`navigate`, `refresh`, `useRefetchable`).

```rescript
@module("virtual:weft/assets") external assets: WeftServer.Page.assets = "default"

let notePage: Servy.Handler.t = async ctx =>
  WeftServer.Page.respond(ctx.request, <NotePage id />, ~assets, ~title="Note")
```

The HTML is one streamed response, the page rendered as HTML for the browser to show before any
JavaScript runs, and the payload for the client to hydrate it with:

1. the document's head (the bootstrap's script, `async` so it runs as soon as it's loaded, and its
   preloads and stylesheets), at once, but for its end;
2. once the shell is ready (everything outside `Suspense` boundaries that are still pending), the
   rest of the head: links to the stylesheets the rows so far need (the CSS of what the shell
   rendered, which the browser then shows it with, never without) and preloads for the chunks of
   the entrypoints it uses; then `<div id="root" data-weft-html>` with the shell's HTML in it;
3. each row of the payload as an inline script (the ones that came before the shell, then each as
   the server writes it), and each pending boundary's content as `WeftDom.Html` has it ready, with
   the inline runtime that swaps it in.

The payload is rendered once (server components run once): its rows go to the page, and are decoded
on the server too, exactly as the browser will (`Decoder`, loading entrypoints with
`assets.loadModule`), for `WeftDom.Html` to render, inside a server-side page
(`Navigation.makeForServer`) so entrypoints can call `useNavigation`. The bootstrap (`Bootstrap`)
reads the rows from the inline scripts, whether they ran before it loaded or after, and hydrates
`#root`.

If the shell fails (an error outside every boundary), or the root row does, the page is the rows
alone, with an empty `#root`, for the client to render (and to throw the error again where an
`ErrorBoundary` can catch it). Without `assets.loadModule`, or with `~html=false`, it's always that.
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
  /**
  Loads an entrypoint file on the server, for rendering the page's HTML (the plugin's
  `virtual:weft/ssr-references`). Without it, a page is the rows alone.
  */
  loadModule?: Decoder.loadModule,
  /**
  The app's stylesheets (`weft_css`'s), by sheet id: `Render` sends the ones a page uses (see its
  `styles`), and the page links the shell's. Without them, no stylesheets are sent.
  */
  sheets?: dict<Render.sheet>,
  /** Each entrypoint file's stylesheets (those its code imports), by file id. */
  entrypointSheets?: dict<array<string>>,
}

/**
The HTML page for `element`, streamed as it renders. `url` (the request's path and query, `"/"` by
default) is what the server-side page says it is; `html=false` leaves the HTML out. `title` and
`head` (raw HTML, for anything else the head needs) go in the head. `onError` sees every error, once:
the server components' (from `Render`) and the client components' (from `WeftDom.Html`). `signal`
stops everything.
*/
let toStream: (
  Weft.Element.t,
  ~assets: assets,
  ~url: string=?,
  ~html: bool=?,
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
  Weft.Element.t,
  ~assets: assets,
  ~html: bool=?,
  ~title: string=?,
  ~head: string=?,
  ~onError: exn => option<string>=?,
) => Response.t
