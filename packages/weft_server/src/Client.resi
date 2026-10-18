/***
The client: turns a payload from `Render` back into elements, as it streams in, for a renderer
(`WeftDom.Client`, or a test's `TestRenderer`) to render.

```rescript
let client = WeftServer.Client.make(~loadModule=id => loadEntrypointFile(id))
let element = await client->WeftServer.Client.fetchElement("/notes/1")
root->WeftDom.Client.render(element)
```

The promise resolves once the root row is in and every entrypoint it refers to has loaded; the rest
of the payload keeps streaming in after that. Each part that wasn't ready when the server wrote the
root arrives as a `WeftCore.Lazy` element, which renders as soon as its row does (and suspends to
its `Suspense` boundary until then). A row that has arrived is readable at once (see
`WeftCore.Deferred`), so rendering a payload that has fully arrived never suspends.

Entrypoint modules are loaded once per client, not once per payload, so the same entrypoint in two
payloads is the same component type: rendering a refetched payload over the one on screen keeps the
state of entrypoints in the same place, and patches only what changed, as any other update does.
*/

/** A `ReadableStream` of bytes. */
type stream = Streams.t

/** An `AbortSignal`. */
type signal = Streams.Signal.t

/**
Loads an entrypoint's file: given its id (`<package>/<path>`, the part of an entrypoint's id before
`#`), the module object of the compiled file. The Vite plugin's reference map provides this.
*/
type loadModule = string => promise<unknown>

/** Fetches the payload for a URL, as a stream. */
type fetch = (string, ~signal: signal) => promise<stream>

type t

/** A client, loading entrypoints with `loadModule`, and fetching payloads with `fetch`. */
let make: (~loadModule: loadModule, ~fetch: fetch=?) => t

/**
The root element of the payload `stream`. Rejects if the root row is an error, or the stream ends
before it arrives (or `signal` is aborted first). Aborting `signal` cancels the stream: the other
rows that haven't arrived then never do, and what's waiting on them (a `Suspense` boundary's fallback, say) goes on waiting, rather than failing,
since it may still be on screen until whatever replaces it is ready.
*/
let fromStream: (t, stream, ~signal: signal=?) => promise<WeftCore.Element.t>

/**
`fromStream` for a payload whose root is any value, not just an element (an RPC's response, whose
root is its result).
*/
let valueFromStream: (t, stream, ~signal: signal=?) => promise<unknown>

/** Fetches `url`'s payload with the client's `fetch`, and decodes it (`fromStream`). */
let fetchElement: (t, string, ~signal: signal=?) => promise<WeftCore.Element.t>

/**
`fetch` for the browser: the global `fetch`, asking for the bare payload
(`Accept: text/x-weft-payload`), failing on a status other than 2xx.
*/
let webFetch: fetch

/**
Fetches that replace each other: starting one cancels the one before, and only the latest's element
is returned, so a slow response can't land after a newer one. (Navigation and refetching a part of
the page go through one of these.)
*/
module Latest: {
  type client = t
  type t
  let make: unit => t
  /** `Some(element)` if this is still the latest fetch once it's done; `None` if another replaced it. */
  let fetchElement: (t, client, string) => promise<option<WeftCore.Element.t>>
}
