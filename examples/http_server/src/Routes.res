/***
The example server, built with `@e-cline/server`.

`routes` declares every route, each a method, a path as a list of segments,
and a handler. `make` puts the application together, middleware first and
routes last, as a standard fetch handler (a function from a Web `Request` to
a `Response`) that `Main.res` serves.
*/

module App = Server.App
module RequestContext = Server.RequestContext
module Context = Server.Context
module Handler = Server.Handler
module Html = Server.Html
module Middleware = Server.Middleware
module Query = Server.Query
module Respond = Server.Respond
module Route = Server.Route
module Router = Server.Router

/** What the index page lists. */
let routeDescriptions = [
  ("GET", "/", "This page (HTML)"),
  ("GET", "/hello", "A plain-text greeting; try /hello?name=Ada"),
  ("GET", "/hello/:name", "The same, with the name as a path segment"),
  ("GET", "/time", "The current time (JSON)"),
  ("POST", "/echo", "Sends the request body back, with its content type"),
  (
    "GET",
    "/events",
    "A streamed response: one JSON object per line (NDJSON); try /events?count=10&intervalMs=250",
  ),
  ("ANY", "/inspect", "Describes the request: method, URL, query, headers, body (JSON)"),
  ("GET", "/notes", "The notes so far (JSON)"),
  ("POST", "/notes", "Adds a note; needs `Authorization: Bearer secret-token`"),
]

// -- HTML

let index: Handler.t = async _ctx => {
  let rows =
    routeDescriptions->Array.map(((method, path, description)) =>
      Html.html`<tr><td>${Html.text(method)}</td><td><code>${Html.text(
        path,
      )}</code></td><td>${Html.text(description)}</td></tr>`
    )
  Respond.html(
    Html.html`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>ReScript HTTP server</title>
  </head>
  <body>
    <h1>ReScript HTTP server</h1>
    <p>Built with <code>@e-cline/server</code>.</p>
    <table>
      <thead><tr><th>Method</th><th>Path</th><th>What it does</th></tr></thead>
      <tbody>
        ${rows->Html.join(~separator=Html.raw("\n        "))}
      </tbody>
    </table>
  </body>
</html>
`,
  )
}

// -- Text

let greet = (name: string): Response.t => Respond.text(`Hello, ${name}!\n`)

/** `/hello?name=Ada`: the name comes from the query string. */
let hello: Handler.t = async ctx => greet(ctx.query->Query.getOr("name", "world"))

/** `/hello/:name`: the name is the path segment the route bound as `name`. */
let helloName: Handler.t = async ctx => greet(ctx->RequestContext.paramOrThrow("name"))

// -- JSON

let time: Handler.t = async _ctx => {
  let now = Date.make()
  Respond.json(
    JSON.Encode.object(
      dict{
        "iso": JSON.Encode.string(now->Date.toISOString),
        "epochMs": JSON.Encode.float(now->Date.getTime),
      },
    ),
  )
}

let errorJson = (~status, message) =>
  Respond.json(~status, JSON.Encode.object(dict{"error": JSON.Encode.string(message)}))

// -- Using the request

/** Sends the body back unchanged, labelled with the content type it arrived with. */
let echo: Handler.t = async ctx => {
  let body = await ctx->RequestContext.text
  let contentType =
    ctx->RequestContext.header("content-type")->Option.getOr("text/plain; charset=utf-8")
  Respond.text(~headers=dict{"content-type": contentType}, body)
}

/** A map of strings as a JSON object. */
let encodeStringMap = (map: Map.t<string, string>): JSON.t =>
  map
  ->Map.entries
  ->Iterator.toArray
  ->Array.map(((name, value)) => (name, JSON.Encode.string(value)))
  ->Dict.fromArray
  ->JSON.Encode.object

/** Reports what the server saw: method, URL parts, headers, and the body as text. */
let inspect: Handler.t = async ctx => {
  let body = await ctx->RequestContext.text
  Respond.json(
    JSON.Encode.object(
      dict{
        "method": JSON.Encode.string(ctx.method->Server.Method.toString),
        "url": JSON.Encode.string(ctx.url.href),
        "path": JSON.Encode.string(ctx.url.pathname),
        "segments": RequestContext.pathSegments(ctx.url.pathname)
        ->List.toArray
        ->Array.map(JSON.Encode.string)
        ->JSON.Encode.array,
        "query": ctx.query->Query.toMap->encodeStringMap,
        "headers": ctx.request.headers->Server.HttpHeaders.toMap->encodeStringMap,
        "body": body == "" ? JSON.Encode.null : JSON.Encode.string(body),
      },
    ),
  )
}

// -- Streaming

let sleep = ms => Promise.make((resolve, _reject) => setTimeout(() => resolve(), ms)->ignore)

/**
`/events?count=5&intervalMs=500`: `count` events, one every `intervalMs`
milliseconds, as NDJSON. Each line is sent when its event happens, so a client
sees them arrive one at a time (`curl -N` shows this).
*/
let events: Handler.t = async ctx => {
  let intParam = (name, ~default, ~max) =>
    ctx.query->Query.getInt(name)->Option.getOr(default)->Int.clamp(~min=0, ~max)
  let count = intParam("count", ~default=5, ~max=100)
  let intervalMs = intParam("intervalMs", ~default=500, ~max=5000)

  let sent = ref(0)
  Respond.ndjson(async () =>
    if sent.contents >= count {
      None
    } else {
      // The first event goes out immediately; later ones wait for their turn.
      if sent.contents > 0 {
        await sleep(intervalMs)
      }
      let index = sent.contents
      sent := index + 1
      Some(
        JSON.Encode.object(
          dict{
            "index": JSON.Encode.int(index),
            "of": JSON.Encode.int(count),
            "time": JSON.Encode.string(Date.make()->Date.toISOString),
          },
        ),
      )
    }
  )
}

// -- Context and middleware

// What middleware attach to a request, and the handlers behind them read
// back. Each value has a typed key: the notes are found with `notesKey` and
// nothing else, and what comes back is a `Notes.t`.

/** The notes, shared by every request. Attached by `make`, for every route. */
let notesKey: Context.Key.t<Notes.t> = Context.Key.make(~name="notes")

/** Who is asking. Attached by `requireUser`, so only for the routes behind it. */
let userKey: Context.Key.t<string> = Context.Key.make(~name="user")

/**
Lets a request through only with a known API token, as
`Authorization: Bearer <token>`, and attaches whose token it was. `tokens`
are the tokens, and whose they are.

They're in a `Map`, not a `dict`, because the one being looked up comes from
the client: in a `dict`, `"constructor"` would be found, and let anyone in.
*/
let requireUser = (tokens: Map.t<string, string>): Middleware.t =>
  next =>
    async ctx => {
      let user = ctx->RequestContext.bearerToken->Option.flatMap(token => tokens->Map.get(token))
      switch user {
      | Some(user) => await next(ctx->RequestContext.set(userKey, user))
      | None =>
        errorJson(~status=401, "Missing or unknown API token")->Respond.withHeader(
          "www-authenticate",
          "Bearer",
        )
      }
    }

let listNotes: Handler.t = async ctx => {
  let notes = ctx->RequestContext.getOrThrow(notesKey)
  Respond.json(notes->Notes.all->Array.map(Notes.toJson)->JSON.Encode.array)
}

/**
Adds a note from a JSON body like `{"text": "..."}`, as the authenticated user. The body has to be
sent as `application/json`. Must be behind `requireUser`: without it there's no user, and
`getOrThrow` fails the request.
*/
let createNote: Handler.t = async ctx => {
  let notes = ctx->RequestContext.getOrThrow(notesKey)
  let author = ctx->RequestContext.getOrThrow(userKey)
  switch await ctx->RequestContext.json {
  | Ok(Object(dict{"text": JSON.String(text)})) if text->String.trim != "" =>
    Respond.json(~status=201, notes->Notes.add(~text, ~author)->Notes.toJson)
  | Ok(_) => errorJson(~status=400, `Expected a JSON object with a non-empty "text" string`)
  | Error(WrongContentType(_) as error) =>
    errorJson(~status=415, RequestContext.bodyErrorMessage(error))
  | Error(Malformed(message)) => errorJson(~status=400, `Invalid JSON: ${message}`)
  }
}

let notFound: Handler.t = async ctx =>
  errorJson(~status=404, `No route for ${ctx.method->Server.Method.toString} ${ctx.url.pathname}`)

// -- Routing

/** The routes. `tokens` are the API tokens that may add notes, and whose they are. */
let routes = (~tokens: Map.t<string, string>): array<Route.t> => [
  Route.get(list{}, index),
  Route.get(list{"hello"}, hello),
  Route.get(list{"hello", ":name"}, helloName),
  Route.get(list{"time"}, time),
  Route.post(list{"echo"}, echo),
  Route.get(list{"events"}, events),
  Route.any(list{"inspect"}, inspect),
  Route.get(list{"notes"}, listNotes),
  // Adding a note is behind the middleware that checks the token.
  Route.scope(list{"notes"}, [requireUser(tokens)], [Route.post(list{}, createNote)]),
  // Anything else, in place of the router's plain 404.
  Route.any(list{"**"}, notFound),
]

let onError = (error: exn, _request: Request.t): Response.t => {
  Console.error(error)
  errorJson(~status=500, "Internal server error")
}

/**
The application, put together from the outside in: each middleware goes
around everything after it, and the routes come last.

- `log` receives a line per request; by default nothing is logged.
- `notes` is the store to use; by default a new, empty one.
- `tokens` are the API tokens, and whose they are.
*/
let make = (
  ~log: option<string => unit>=?,
  ~notes: Notes.t=Notes.make(),
  ~tokens: Map.t<string, string>=Map.fromArray([("secret-token", "ada")]),
): App.t =>
  App.build(~onError)
  ->App.use(
    switch log {
    | Some(log) => Middleware.logger(~log)
    | None => Middleware.none
    },
  )
  ->App.use(Middleware.provide(notesKey, notes))
  ->App.router(routes(~tokens))

/** The application with default settings, for running from JavaScript (see `serve.mjs`). */
let app = make(~log=Console.log)
