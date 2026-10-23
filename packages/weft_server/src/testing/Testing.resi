/***
Helpers for testing server components in one process, with nothing real between the server and the
client (tier 1 of the plan's tests): a stream between `Render` and `Client` that the test controls,
and entrypoint modules served from a map.

```rescript
let modules = Testing.modules([("example/src/Likes.res", Testing.module_([("make", Likes.make)]))])
let client = Decoder.make(~loadModule=Testing.loadModule(modules))
let pipe = Testing.pipe(Render.toStream(<Page />), ~delivery=Manual)
let element = client->Decoder.fromStream(Testing.stream(pipe))
pipe->Testing.deliver // the next chunk the server wrote
```

The server's code and the client's share one module graph here, which is fine for these tests but
not for an app's: an app's tests use the Vite plugin's harness, which keeps them apart.
*/

/** When the client gets what the server writes. */
type delivery =
  /** As soon as it's written. */
  | Immediate
  /** One chunk per `deliver`. */
  | Manual

/** How what the server writes is cut up on the way. */
type chunking =
  /** In the chunks the server wrote. */
  | AsWritten
  /** In pieces of at most this many bytes (cutting rows, and characters, anywhere). */
  | EveryBytes(int)

/** The server's stream on its way to the client. */
type pipe

let pipe: (Streams.t, ~delivery: delivery=?, ~chunking: chunking=?) => pipe

/** The end the client reads. */
let stream: pipe => Streams.t

/** With `Manual` delivery: hands the client the next chunk, returning whether there was one. */
let deliver: pipe => bool

/** Hands the client every chunk waiting. */
let deliverAll: pipe => unit

/** With `Manual` delivery: how many chunks are waiting. */
let waiting: pipe => int

/** Resolves once the server's stream has ended. */
let finished: pipe => promise<unit>

/** Everything the server has written so far, as text. */
let written: pipe => string

/** Whether the client cancelled the stream (a newer fetch replaced it, say). */
let cancelled: pipe => bool

/** Reads a whole payload as text, for tests of what the server writes. */
let readAll: Streams.t => promise<string>

/** Entrypoint modules, served from a map, for `Decoder.make`'s `~loadModule`. */
type modules

/** Modules by file id (`<package>/<path>`, the part of an entrypoint's id before `#`). */
let modules: array<(string, unknown)> => modules

/** A module object with these exports. */
let module_: array<(string, unknown)> => unknown

/** A component, as an export for `module_`. */
external component: Weft.JsxCore.component<'props> => unknown = "%identity"

let loadModule: modules => Decoder.loadModule

/** The files loaded so far, in order. */
let loads: modules => array<string>

/** Holds loads back (they wait) until `release`. */
let hold: modules => unit

let release: modules => unit

/** Waits for a macrotask: long enough for the renderer to flush what it has written. */
let tick: unit => promise<unit>
