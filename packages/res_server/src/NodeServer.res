/***
Running an application on Node's `http` server, using
[`@hono/node-server`](https://github.com/honojs/node-server) to convert
between Node's requests and responses and the Web-standard ones.
*/

/** The Node `http.Server`. */
type t

type address = {
  address: string,
  port: int,
  family: string,
}

type options = {
  fetch: App.t,
  port?: int,
  hostname?: string,
}

@module("@hono/node-server")
external serveWithOptions: (options, address => unit) => t = "serve"

@send external on: (t, string, JsExn.t => unit) => unit = "on"
@send external once: (t, string, 'event => unit) => unit = "once"
@send external removeListener: (t, string, 'event => unit) => unit = "removeListener"

/**
Starts serving `app`. `onListen` is called once the server is accepting
connections.

- `port` is 3000 unless told otherwise. Port 0 picks any free port, which
  `onListen`'s argument reports.
- `hostname` is the address to listen on, by default `127.0.0.1`: this
  machine only. To accept connections from other machines, as a deployed
  server or one in a container must, say so with `~hostname="0.0.0.0"` (or
  `"::"` for IPv6 as well).

`onServerError` is called if the server itself fails: most often because it
can't listen, the port being in use (the error's `code` is `EADDRINUSE`).
Without it, such an error is thrown, which ends the process.
*/
let serve = (
  ~port: int=3000,
  ~hostname: string="127.0.0.1",
  ~onListen: address => unit=_ => (),
  ~onServerError: option<JsExn.t => unit>=?,
  app: App.t,
): t => {
  let server = serveWithOptions({fetch: app, port, hostname}, onListen)
  onServerError->Option.forEach(onServerError => server->on("error", onServerError))
  server
}

/**
Like `serve`, as a promise of the server and its address once it's listening.
The promise is rejected if the server can't listen.
*/
let listen = (~port: option<int>=?, ~hostname: option<string>=?, app: App.t): promise<(
  t,
  address,
)> =>
  Promise.make((resolve, reject) => {
    let server = ref(None)
    let fail = (error: JsExn.t) => reject(error)
    let started = serve(
      ~port?,
      ~hostname?,
      // `onListen` runs asynchronously, after `serve` has returned.
      ~onListen=address =>
        server.contents->Option.forEach(server => {
          // From here on a failure isn't a failure to start.
          server->removeListener("error", fail)
          resolve((server, address))
        }),
      app,
    )
    started->once("error", fail)
    server := Some(started)
  })

/**
Starts building an application that is served once it has its handler: like
`App.build`, but the pipe ends with a running server.

```rescript
NodeServer.run(~port=3000)
->App.use(Middleware.logger())
->App.router([Route.get(list{}, home)])
```

`port`, `hostname`, `onListen` and `onServerError` are as for `serve`, and
`onError` as for `App.build`.
*/
let run = (
  ~port: option<int>=?,
  ~hostname: option<string>=?,
  ~onListen: option<address => unit>=?,
  ~onServerError: option<JsExn.t => unit>=?,
  ~onError: option<App.onError>=?,
): App.builder<t> =>
  App.build(~onError?)->App.map(app => serve(~port?, ~hostname?, ~onListen?, ~onServerError?, app))

@send external closeWithCallback: (t, Nullable.t<JsExn.t> => unit) => unit = "close"
@send external closeIdleConnections: t => unit = "closeIdleConnections"

/** Stops accepting connections, resolving once the open ones have finished. */
let close = (server: t): promise<unit> =>
  Promise.make((resolve, reject) => {
    server->closeWithCallback(error =>
      switch error->Nullable.toOption {
      | Some(error) => reject(error)
      | None => resolve()
      }
    )
    server->closeIdleConnections
  })
