# @e-cline/weft_server

Server components for Weft: render a component tree on the server into a streamed payload, and turn
it back into elements on the client as it arrives, with interactive components (entrypoints) loaded
on demand, pages that stream, navigate and fetch parts of themselves again, and RPCs; and the pages
rendered as HTML on the server, then hydrated. It's phases 3, 5 and 6 of
[the server components plan](../../docs/weft_server_components_plan.md), and the pages' HTML is
[its own plan](../../docs/weft_ssr_hydration_plan.md).
[The Vite plugin](../../tools/weft_vite_plugin) bundles an app using it, and
[`examples/weft_notes`](../../examples/weft_notes) is one.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/weft_server @e-cline/weft rescript @rescript/runtime
```

Add `@e-cline/weft_server` and `@e-cline/weft` to the `dependencies` in your `rescript.json` (and
`@rescript/webapi`, whose `Request.t` and `Response.t` `Page.respond` takes and returns). Components
are marked with `@weft.component({kind: Server})` and `@weft.component({kind: Entrypoint})`, which
need [the `ppx_weft` PPX](../../tools/ppx/weft).

## Using it

On the server, a route answers with a page (here, an `@e-cline/servy` handler):

```rescript
@module("virtual:weft/assets") external assets: WeftServer.Page.assets = "default"

let notePage: Servy.Handler.t = async ctx =>
  WeftServer.Page.respond(ctx.request, <NotePage id={ctx->RequestContext.paramOrThrow("id")} />, ~assets)
```

A first request gets the HTML page: the page itself, rendered on the server (`WeftDom.Html`), so it
shows before any JavaScript runs, streamed (each `Suspense` boundary's content follows once it's
ready), with the payload's rows as inline scripts. The payload is rendered once: its rows go to the
page, and are decoded on the server too, as the browser will, for the HTML. The client's own
requests (`Accept: text/x-weft-payload`) get the bare payload. With the plugin,
`virtual:weft/assets` gives the server what it needs (`assets.loadModule`); `~html=false` leaves the
HTML out of a route's pages.

**Entrypoints run on the server too**, to render that HTML: their hooks give their initial state and
their effects don't run. So an entrypoint file (and what it imports) mustn't touch the DOM, `window`
or `document` at the top level of a module or while rendering, only in handlers and effects. If one
does, rendering it on the server fails (the error goes to `onError`), and the browser renders it
instead: its `Suspense` boundary, or, outside every boundary, the whole page, as with `~html=false`.
A store read with `useSyncExternalStore` needs a `~getServerSnapshot`.

In the browser, `Bootstrap.start` reads those rows and hydrates `#root` with them: the server's
nodes adopted, not rendered again (the Vite plugin's default bootstrap calls it). From there, the
page is a `Navigation.t`, which entrypoints reach with hooks:

```rescript
// in an entrypoint
let navigation = WeftServer.Navigation.useNavigation()
navigation->WeftServer.Navigation.navigate("/notes/2") // fetch the payload, render it in place
navigation->WeftServer.Navigation.refresh              // fetch this page's again
```

A link's `onClick` should use `followLink`, which navigates in place only for a plain click on a
link to this origin, and leaves the rest to the browser (one opening a new tab or window, a
`download`, a `target`, a link to a part of the page):

```rescript
<a href onClick={event => navigation->WeftServer.Navigation.followLink(event, ~href)->ignore}>
  children
</a>
```

If a page can't be shown in place (its payload couldn't be fetched, or its root failed), the
browser's navigation loads it the ordinary way instead, so the server's own answer is what's seen. A
`refresh` that fails rejects instead, keeping what's on the page.

Part of the page can be fetched again by itself. In an entrypoint, `useRefetchable` does it with the
parts that are easy to get wrong by hand done (newer `children` from a refresh winning over what was
refetched, fetches replacing each other, rendering in a transition):

```rescript
// in a server component: the comments, rendered here, given to an entrypoint as children
<CommentsPanel noteId=id> <Comments id /> </CommentsPanel>

// in CommentsPanel, the entrypoint
let comments = WeftServer.Navigation.useRefetchable(~src=`/notes/${noteId}/comments`, children)
<div>
  <button onClick={_ => comments.refetch()->ignore}> {WeftDom.Jsx.string(comments.isPending ? "…" : "Reload")} </button>
  {comments.element}
</div>
```

The route at `src` renders just that part (`<Comments id />`), with `Page.respond`.

### RPCs

A Weft RPC is a function that runs on the server, which the client calls as if it were local:
`'input => promise<result<'response, Rpc.error<'error>>>`, whose promise never rejects. It's
declared in shared code, with an ID, how its request goes over the wire (a codec), and what to check
first. The declaration needs its type written out: nothing else says what the response is.

```rescript
// src/Api.res: shared
type addComment = {noteId: string, text: string}

@weft.rpc({id: "notes.addComment"})
let addComment: WeftServer.Rpc.t<addComment, addComment, Types.comment, error> =
  WeftServer.Rpc.makePrepared(
    ~request=Codec.object2(
      ("noteId", Codec.string),
      ("text", Codec.string),
      (noteId, text) => {noteId, text},
      ({noteId, text}) => (noteId, text),
    ),
    // On the client, before anything is sent. (`Rpc.make` has none: its input is the request.)
    ~prepare=async ({noteId, text}) =>
      String.trim(text) == "" ? Error(EmptyComment) : Ok({noteId, text: String.trim(text)}),
    // On both sides: the server can't count on the client having checked.
    ~check=({text}) => String.length(text) > 500 ? Error(TooLong) : Ok(),
  )
```

It's handled in a server-only file, and the server answers the RPCs a router lists:

```rescript
// src/ApiServer.res
@@weft.server

let addComment = WeftServer.RpcServer.handler(Api.addComment, async ({noteId, text}, ~http as _) =>
  Ok(Db.addComment(noteId, text))
)
let router = WeftServer.RpcServer.router([addComment])

// src/Server.res
Route.post(list{"_weft", "rpc", ":id"}, async ctx =>
  await ApiServer.router->WeftServer.RpcServer.respond(ctx.request, ~id=ctx->RequestContext.paramOrThrow("id"))
)
```

An entrypoint calls it with `Rpc.use` (or anything else with `Rpc.call` and a client):

```rescript
let addComment = WeftServer.Rpc.use(Api.addComment)
switch await addComment({noteId, text}) {
| Ok(comment) => ...
| Error(Rejected(error)) => ... // prepare, check, or the handler said no
| Error(Invalid(_)) => ...      // the server couldn't read the request (an older client, say)
| Error(Failed(problem)) => ... // the network, an unknown RPC, a handler that threw
}
```

- **Requests are plain JSON**, written and read by the codec (`Rpc.Codec`: `string`, `int`, `float`,
  `bool`, `option`, `array`, `dict`, `date`, `object1` to `object8`, `variant`, `map`, `custom`),
  never by the payload decoder, which follows references and loads modules: right for the server's
  own output, wrong for a stranger's. A codec reads only the fields it knows, as own properties, and
  builds values afresh, so a request can't reach a prototype.
- **Responses are payloads**, so they can be or contain elements (server components' output) and
  promises, which stream in after the response.
- **The router** answers only the IDs it was given (a `Map`, never a property lookup), and only a
  `POST` of `application/json` with the `x-weft-rpc: 1` header from an allowed `Origin` (CSRF), with
  a body under its limit (64 KB by default). It never calls a handler with a request its codec
  didn't read and `check` didn't accept. Every RPC it lists is public: authentication is the
  handler's (`~http`), or a middleware's.

### The lower levels

The lower levels are there too: `Render.toStream(element)` (the payload, as a `ReadableStream`), and
`Decoder.make(~loadModule)` with `Decoder.fetchElement(url)` (a decoded element, to render
anywhere). `loadModule` loads an entrypoint's compiled file, given its id: the Vite plugin provides
it (`virtual:weft/client`); in tests, it's `Testing.loadModule`.

## Where it runs

The sources are in `src/client/`, `src/server/` and `src/shared/` by where they run (and
`src/testing/`). The server-only modules start with the `'use weft server'` directive, so the Vite
plugin refuses them to an app's client build, naming the chain of imports, as it does the app's own
server files.

| Module       | Where   | What it is                                                                      |
| ------------ | ------- | ------------------------------------------------------------------------------- |
| `Render`     | server  | The server renderer: an element tree into a payload.                            |
| `Page`       | server  | A page's response: the HTML shell with the payload's rows, or the bare payload. |
| `RpcServer`  | server  | RPCs' handlers, and the router that answers them.                               |
| `Decoder`    | both    | A payload back into elements, entrypoints loaded on demand.                     |
| `Navigation` | both    | The page: `navigate`, `refresh`, `useNavigation`, `useRefetchable`.             |
| `Rpc`        | both    | Declaring RPCs, and calling them (`call`, `use`). `Rpc.Codec`: their codecs.    |
| `Payload`    | both    | The wire format.                                                                |
| `Bootstrap`  | browser | The browser's start: the rows from the page, rendered into `#root`.             |
| `Testing`    | tests   | `Render` and `Decoder` connected in one process, with the test in control.      |

## How it works

- **`Render`** walks the tree with no fibers. Server and shared components are called, and only
  their output is sent. A keyed one's output goes in a fragment with that key, since it leaves no
  fiber on the client to carry it. Entrypoints are sent as references with their props, which must
  be serializable: strings, numbers, booleans, `bigint`, records, variants, options, arrays, dicts,
  dates, elements and promises. Functions, class instances and cycles fail, with a development-build
  message saying where they are.
- **`Suspense` boundaries are the unit of streaming.** Work that isn't ready is waited for outside
  every boundary. Under one, it's sent as a placeholder, and its content follows in a row of its
  own. Errors under a boundary are sent in place, for an `ErrorBoundary` in an entrypoint to catch.
- **`Decoder`** decodes rows as they come in. A row that has arrived can be read straight away
  (`Weft.Deferred`), so a payload that has fully arrived renders without suspending.
- **Modules are cached per client, not per payload**, so rendering a refetched payload over the one
  on screen patches it in place: entrypoints in the same place keep their state and get the new
  props, and host nodes are reused. `Decoder.Latest` runs fetches that replace each other, so a slow
  response can't land after a newer one.
- **`Payload`** documents the format: newline-separated rows, `<id>:<tag><json>`.
- **`Page`** streams the HTML: the head (the bootstrap's script, `async`, so it runs before the page
  has finished streaming), `<div id="root">` with the shell in it, then each row as an inline script
  that pushes it onto `self.__weft`, escaped so nothing in it can end the script, with a
  `modulepreload` for an entrypoint's chunk before the first row using it, and each boundary's
  segment as it's ready. `Bootstrap.rows` reads the rows back, whether they were pushed before it
  started or after; `Bootstrap.main`, run before `#root` has been parsed, waits for it.
- **`Navigation`** renders each fetched payload over the screen in a transition, so boundaries
  already showing keep their content until what replaces it is ready. A fetch replaces the one
  before (`Decoder.Latest`): the older is cancelled, and what it hadn't delivered is left waiting,
  not failed, since it may still be on screen until the newer has rendered.
- **`useRefetchable`** shows its `children` until it's refetched, then what it fetched, until newer
  `children` come with a `navigate` or `refresh`: whichever is newer wins.
- **Keys** in lists a server component built at runtime are checked on the server (a development
  build warns, naming where the list is), since the client can't tell them from lists written out in
  JSX once they've been through the payload.

## Testing

`WeftServer.Testing` connects `Render` to `Decoder` in one process. It has a pipe whose delivery the
test controls (everything at once, one chunk at a time, or re-cut every _n_ bytes), and entrypoint
modules served from a map, whose loads can be held. This package's own tests use it:

- **Unit tests:** the format, the renderer's rows, and the client fed hand-written rows.
- **End-to-end tests:** round trips into weft's `TestRenderer`, including refetches over the screen.
- **A fuzz test:** random trees and refetches, compared with rendering the same trees directly.
- **Pages and navigation:** `Page`'s HTML (the shell, rows that would end a script, preloads, rows
  streaming under a boundary) read back by `Bootstrap.rows`; navigating, refreshing, parts of a page
  refetched with `useRefetchable` (only their subtree changes, pending until rendered, newer content
  winning either way), requests replacing each other, and failures leaving the screen as it was, all
  against a server in the same process (`Support.serve`).
- **RPCs:** codecs round-tripping random values, and refusing what doesn't fit (with where), while
  ignoring unknown fields and prototype names; the router against hand-made requests (unknown IDs,
  prototype names among them, the wrong method, content type, header or origin, bodies too big, not
  JSON, too deep, or not what the codec reads); random bodies (the router never gets a 5xx for one,
  and no handler gets a request its codec wouldn't produce); and calls through the router in process
  (`prepare` sending nothing, aborting, elements and promises in responses, failures).

## Error codes

Production builds throw `WeftServer error <code>` instead of these messages:

| Code | Development message                                                                       |
| ---: | ----------------------------------------------------------------------------------------- |
|    1 | A payload row isn't one.                                                                  |
|    2 | A function can't be sent from the server.                                                 |
|    3 | A host element rendered on the server can't have an event handler.                        |
|    4 | A host element rendered on the server can't have a ref.                                   |
|    5 | A value that can't be sent from the server (a symbol, or an instance of a class).         |
|    6 | A value can't contain itself (a cycle) when it's sent from the server.                    |
|    7 | A context provider can't be rendered on the server.                                       |
|    8 | An `ErrorBoundary` can't be rendered on the server.                                       |
|    9 | A portal can't be rendered on the server.                                                 |
|   10 | A component suspended 100 times in a row (making a new promise every time it's called?).  |
|   11 | An internal element reached the server renderer (a bug in WeftServer).                    |
|   12 | An entrypoint's module doesn't have the module or `make` its id names.                    |
|   13 | The payload ended before a row it referred to arrived.                                    |
|   14 | Fetching a payload failed (a status other than 2xx).                                      |
|   15 | Something in a payload isn't a value (a bug in WeftServer, or a corrupted payload).       |
|   16 | `useNavigation` or `useRefetchable` was called outside a page (`Navigation.show`).        |
|   17 | `Bootstrap.start` found no `#root` in the document.                                       |
|   18 | An RPC's ID isn't one (names separated by dots, each a letter then letters, digits, `_`). |
|   19 | An RPC router was given two handlers for one ID.                                          |
|   20 | The server's page was asked to fetch (`navigate`, `refresh`, a refetch) while rendering.  |

Codes don't change once published: a new error gets the next number.
