/***
An application: a handler turned into a standard fetch handler, a function
from a Web `Request` to a promise of a `Response`. That's the interface
`NodeServer.serve`, `@hono/node-server`'s `serve({fetch})`, Deno, Bun and
Cloudflare Workers all run, and it can be called directly in tests.

One is put together from the outside in, as a pipe: a start, then each
middleware, then the handler the middleware go around.

```rescript
let app =
  App.build()
  ->App.use(Middleware.logger())                  // outermost: sees each request first
  ->App.use(Middleware.provide(poolKey, pool))
  ->App.router([
    Route.get(list{}, home),
    Route.get(list{"users", ":id"}, showUser),
  ])
```

`NodeServer.run` starts the same kind of pipe, and serves the result.

Two things are true of every application, however it's made:

- A request whose path has an unsafe segment (see
  `RequestContext.isSegmentSafe`) is answered with a 400 and doesn't reach the
  handler.
- If the handler throws, or its promise rejects, the response is `onError`'s:
  by default a plain 500, after logging the error.

In an application made with `build`, both of those happen inside the
middleware, so the 400 or the 500 is a response like any other to them: it is
logged, gets its CORS headers, and so on. An error thrown by a middleware
itself has nothing around it but the application, and gets `onError`'s
response as it is.
*/

type t = Request.t => promise<Response.t>

/**
What an application answers with when something throws. If this throws too,
the answer is a plain 500, and what it threw is logged.
*/
type onError = (exn, Request.t) => Response.t

/** Logs the error and answers with a plain 500 that says nothing about it. */
let defaultOnError: onError

/**
An application from a handler directly. Any middleware already around the
handler is outside nothing: an error is answered by `onError` without passing
back through it. Use `build` to have errors pass through the middleware.
*/
let make: (Handler.t, ~onError: onError=?) => t

/**
An application being put together, which will produce a `'result` once it has
its handler. `build` starts one for an `App.t`, and `NodeServer.run` one for a
running server.

Each `use` adds a middleware inside the ones already there, and `handle` or
`router` supplies the handler and finishes.
*/
type builder<'result>

/** Starts building an application. */
let build: (~onError: onError=?) => builder<t>

/**
Adds a middleware. It goes inside every middleware added before it and
outside every one added after, so the first `use` in a pipe is the outermost.
*/
let use: (builder<'result>, Middleware.t) => builder<'result>

/** Finishes with the handler that everything added so far goes around. */
let handle: (builder<'result>, Handler.t) => 'result

/** Finishes with a router for the given routes: `handle(Router.make(routes))`. */
let router: (builder<'result>, array<Route.t>) => 'result

/**
A builder that does something more with its result once it's finished. This
is how `NodeServer.run` is made: `build()->map(app => serve(app))`.
*/
let map: (builder<'a>, 'a => 'b) => builder<'b>
