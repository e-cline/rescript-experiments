# @e-cline/weft_server

Server components for Weft: render a component tree on the server into a streamed payload, and turn
it back into elements on the client as it arrives, with interactive components (entrypoints) loaded
on demand. This is phase 3 of
[the server components plan](../../docs/weft_server_components_plan.md): the payload format, the
renderer and the client, tested in one process. [The Vite plugin](../vite_plugin_weft) bundles an
app using it. Pages, navigation and HTML rendering come in later phases.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/weft_server @e-cline/weft_core rescript @rescript/runtime
```

Add `@e-cline/weft_server` and `@e-cline/weft_core` to the `dependencies` in your `rescript.json`.
Components are marked with `@weft.component({kind: Server})` and
`@weft.component({kind: Entrypoint})`, which need [the `ppx_weft` PPX](../../tools/ppx/weft).

## Using it

On the server:

```rescript
let stream = WeftServer.Render.toStream(<NotePage id />) // a ReadableStream of bytes
```

On the client:

```rescript
let client = WeftServer.Client.make(~loadModule)
let element = await client->WeftServer.Client.fetchElement("/notes/1")
root->WeftDom.Client.render(element)
```

`loadModule` loads an entrypoint's compiled file, given its id.
[The Vite plugin](../vite_plugin_weft) provides it (`virtual:weft/client`); in tests, it's
`Testing.loadModule`.

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

## Testing

`WeftServer.Testing` connects `Render` to `Client` in one process. It has a pipe whose delivery the
test controls (everything at once, one chunk at a time, or re-cut every _n_ bytes), and entrypoint
modules served from a map, whose loads can be held. This package's own tests use it:

- **Unit tests:** the format, the renderer's rows, and the client fed hand-written rows.
- **End-to-end tests:** round trips into weft_core's `TestRenderer`, including refetches over the
  screen.
- **A fuzz test:** random trees and refetches, compared with rendering the same trees directly.

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

Codes don't change once published: a new error gets the next number.
