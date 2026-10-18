/***
The server renderer: renders an element tree, server components and all, into a streamed payload
(see `Payload`) for `Client` to turn back into elements.

```rescript
let stream = WeftServer.Render.toStream(<NotePage id />)
// a ReadableStream of bytes, for a Response body
```

It walks the tree with no fibers:

- Server and shared components are called (through `WeftCore.ServerRender.run`, so hooks that keep
  state fail with a clear error, and `Hooks.use` works), and their output is rendered in turn. A
  keyed one's output is wrapped in a fragment with its key, since it leaves no fiber behind on the
  client to carry it.
- Host elements and their props are written as they are. They can't have event handlers or refs:
  those belong in an entrypoint.
- An entrypoint (a component marked by `WeftCore.Entrypoint.mark`, which `@weft.component({kind:
  Entrypoint})` does) isn't called: it's written as a reference, with its props, which have to be
  serializable (see `Payload`). Element props, `children` included, are rendered here, so server
  components can be passed to entrypoints.
- `Suspense` boundaries are the unit of streaming. Work that isn't ready (an async server
  component's `Lazy` element, or a component suspended on `Hooks.use`) is waited for if no
  `Suspense` is above it in the tree; under one, it's written as a placeholder, and the rest carries
  on, with the content following in a row of its own once it's ready. Independent work runs
  concurrently, and rows are written in the order they finish, batched per macrotask.
- A promise passed as a prop is written as a reference, and settled by a later row, so an
  entrypoint can read it with `Hooks.use`.
- An error under a `Suspense` boundary is written in place of what failed, for the client to throw
  there (for an `ErrorBoundary` in an entrypoint to catch); one outside every boundary fails the
  root. `onError` sees each, and may return a digest to send with it. The message itself is sent
  only in development builds.

The stream ends once every row is written. Cancelling it (the client went away), or aborting
`signal`, stops whatever is pending: nothing more is written, and components waiting on promises
aren't called again.
*/

/** An `AbortSignal`. */
type signal = Streams.Signal.t

/** A `ReadableStream` of bytes. */
type stream = Streams.t

/**
The payload for `element`. `onError` (by default, logging with `Console.error`) is called with each
error, and returns the digest to send with it, if any.
*/
let toStream: (WeftCore.Element.t, ~onError: exn => option<string>=?, ~signal: signal=?) => stream
