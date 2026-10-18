# @e-cline/weft_server

Server components for Weft: render a component tree on the server into a streamed payload, and turn
it back into elements on the client as it arrives, with interactive components (entrypoints) loaded
on demand, and pages that stream, navigate and fetch parts of themselves again. It's phases 3 and 5
of [the server components plan](../../docs/weft_server_components_plan.md).
[The Vite plugin](../vite_plugin_weft) bundles an app using it, and
[`examples/weft_notes`](../../examples/weft_notes) is one. HTML rendering (and hydration) comes
later.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/weft_server @e-cline/weft_core rescript @rescript/runtime
```

Add `@e-cline/weft_server` and `@e-cline/weft_core` to the `dependencies` in your `rescript.json`
(and `@rescript/webapi`, whose `Request.t` and `Response.t` `Page.respond` takes and returns).
Components are marked with `@weft.component({kind: Server})` and
`@weft.component({kind: Entrypoint})`, which need [the `ppx_weft` PPX](../../tools/ppx/weft).

## Using it

On the server, a route answers with a page (here, an `@e-cline/servy` handler):

```rescript
@module("virtual:weft/assets") external assets: WeftServer.Page.assets = "default"

let notePage: Servy.Handler.t = async ctx =>
  WeftServer.Page.respond(ctx.request, <NotePage id={ctx->RequestContext.paramOrThrow("id")} />, ~assets)
```

A first request gets the HTML page, with the payload's rows streamed into it as inline scripts; the
client's own requests (`Accept: text/x-weft-payload`) get the bare payload.

In the browser, `Bootstrap.start` reads those rows and renders them into `#root` (the Vite plugin's
default bootstrap calls it). From there, the page is a `Navigation.t`, which entrypoints reach with
hooks:

```rescript
// in an entrypoint
let navigation = WeftServer.Navigation.useNavigation()
navigation->WeftServer.Navigation.navigate("/notes/2") // fetch the payload, render it in place
navigation->WeftServer.Navigation.refresh              // fetch this page's again
```

Part of the page can be fetched again by itself. In an entrypoint, `useRefetchable` does it with the
parts that are easy to get wrong by hand done (newer `children` from a refresh winning over what was
refetched, fetches replacing each other, rendering in a transition):

```rescript
// in a server component: the comments, rendered here, given to an entrypoint as children
<CommentsPanel noteId=id> <Comments id /> </CommentsPanel>

// in CommentsPanel, the entrypoint
let comments = WeftServer.Navigation.useRefetchable(~src=`/notes/${noteId}/comments`, children)
<div>
  <button onClick={_ => comments.refetch()->ignore}> {Weft.Jsx.string(comments.isPending ? "…" : "Reload")} </button>
  {comments.element}
</div>
```

The route at `src` renders just that part (`<Comments id />`), with `Page.respond`.

The lower levels are there too: `Render.toStream(element)` (the payload, as a `ReadableStream`), and
`Client.make(~loadModule)` with `Client.fetchElement(url)` (a decoded element, to render anywhere).
`loadModule` loads an entrypoint's compiled file, given its id: the Vite plugin provides it
(`virtual:weft/client`); in tests, it's `Testing.loadModule`.

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
- **`Client`** decodes rows as they come in. A row that has arrived can be read straight away
  (`WeftCore.Deferred`), so a payload that has fully arrived renders without suspending.
- **Modules are cached per client, not per payload**, so rendering a refetched payload over the one
  on screen patches it in place: entrypoints in the same place keep their state and get the new
  props, and host nodes are reused. `Client.Latest` runs fetches that replace each other, so a slow
  response can't land after a newer one.
- **`Payload`** documents the format: newline-separated rows, `<id>:<tag><json>`.
- **`Page`** streams the HTML: the head (the bootstrap's script, `async`, so it runs before the page
  has finished streaming), `<div id="root">`, then each row as an inline script that pushes it onto
  `self.__weft`, escaped so nothing in it can end the script, with a `modulepreload` for an
  entrypoint's chunk before the first row using it. `Bootstrap.rows` reads them back, whether they
  were pushed before it started or after.
- **`Navigation`** renders each fetched payload over the screen in a transition, so boundaries
  already showing keep their content until what replaces it is ready. A fetch replaces the one
  before (`Client.Latest`): the older is cancelled, and what it hadn't delivered is left waiting,
  not failed, since it may still be on screen until the newer has rendered.
- **`useRefetchable`** shows its `children` until it's refetched, then what it fetched, until newer
  `children` come with a `navigate` or `refresh`: whichever is newer wins.
- **Keys** in lists a server component built at runtime are checked on the server (a development
  build warns, naming where the list is), since the client can't tell them from lists written out in
  JSX once they've been through the payload.

## Testing

`WeftServer.Testing` connects `Render` to `Client` in one process. It has a pipe whose delivery the
test controls (everything at once, one chunk at a time, or re-cut every _n_ bytes), and entrypoint
modules served from a map, whose loads can be held. This package's own tests use it:

- **Unit tests:** the format, the renderer's rows, and the client fed hand-written rows.
- **End-to-end tests:** round trips into weft_core's `TestRenderer`, including refetches over the
  screen.
- **A fuzz test:** random trees and refetches, compared with rendering the same trees directly.
- **Pages and navigation:** `Page`'s HTML (the shell, rows that would end a script, preloads, rows
  streaming under a boundary) read back by `Bootstrap.rows`; navigating, refreshing, parts of a page
  refetched with `useRefetchable` (only their subtree changes, pending until rendered, newer content
  winning either way), requests replacing each other, and failures leaving the screen as it was, all
  against a server in the same process (`Support.serve`).

## Error codes

Production builds throw `WeftServer error <code>` instead of these messages:

| Code | Development message                                                                      |
| ---: | ---------------------------------------------------------------------------------------- |
|    1 | A payload row isn't one.                                                                 |
|    2 | A function can't be sent from the server.                                                |
|    3 | A host element rendered on the server can't have an event handler.                       |
|    4 | A host element rendered on the server can't have a ref.                                  |
|    5 | A value that can't be sent from the server (a symbol, or an instance of a class).        |
|    6 | A value can't contain itself (a cycle) when it's sent from the server.                   |
|    7 | A context provider can't be rendered on the server.                                      |
|    8 | An `ErrorBoundary` can't be rendered on the server.                                      |
|    9 | A portal can't be rendered on the server.                                                |
|   10 | A component suspended 100 times in a row (making a new promise every time it's called?). |
|   11 | An internal element reached the server renderer (a bug in WeftServer).                   |
|   12 | An entrypoint's module doesn't have the module or `make` its id names.                   |
|   13 | The payload ended before a row it referred to arrived.                                   |
|   14 | Fetching a payload failed (a status other than 2xx).                                     |
|   15 | Something in a payload isn't a value (a bug in WeftServer, or a corrupted payload).      |
|   16 | `useNavigation` or `useRefetchable` was called outside a page (`Navigation.show`).       |
|   17 | `Bootstrap.start` found no `#root` in the document.                                      |

Codes don't change once published: a new error gets the next number.
