/***
A middleware is a function from a handler to a handler: given the handler it
wraps (`next`), it returns one that decides whether and how to call it, and
what to do with the response.

```rescript
let timing: Middleware.t = next =>
  async ctx => {
    let start = Date.now()
    let response = await next(ctx)
    response->Respond.withHeader("x-elapsed-ms", (Date.now() -. start)->Float.toString)
  }
```

Middleware go around a whole application with `App.use`, around a group of
routes with `Route.scope`, and around one handler with `apply`. Wherever
several are listed, the first is the outermost: it sees the request first and
the response last.

A middleware can attach a value to the request for the handlers behind it,
by calling `next` with `ctx->RequestContext.set(key, value)`. They read it
back with `RequestContext.get` and the same key (see `Context`):

```rescript
let userKey: Context.Key.t<user> = Context.Key.make(~name="user")

let authenticate: Middleware.t = next =>
  async ctx =>
    switch await findUser(ctx) {
    | Some(user) => await next(ctx->RequestContext.set(userKey, user))
    | None => Respond.text(~status=401, "Unauthorized")
    }
```
*/

type t = Handler.t => Handler.t

/**
The middleware that does nothing: `none->apply(handler)` is `handler`. For
when a middleware is wanted only some of the time:

```rescript
let logging = verbose ? Middleware.logger() : Middleware.none
```
*/
let none: t = handler => handler

/** `handler` wrapped in `middleware`. */
let apply = (middleware: t, handler: Handler.t): Handler.t => middleware(handler)

/**
One middleware from several. The first is outermost, so
`pipeline([a, b])->apply(handler)` is `a->apply(b->apply(handler))`, and
`pipeline([])` is `none`.
*/
let pipeline = (middlewares: array<t>): t =>
  handler => middlewares->Array.reduceRight(handler, (handler, middleware) => middleware(handler))

/**
Attaches the same `value` to every request, under `key`: how handlers get
at something the whole application shares, like a database connection pool
or its configuration.

```rescript
App.build()->App.use(Middleware.provide(poolKey, pool))->App.router(routes)
```
*/
let provide = (key: Context.Key.t<'a>, value: 'a): t =>
  next => ctx => next(ctx->RequestContext.set(key, value))

/** Adds headers to every response, unless the response already sets them. */
let responseHeaders = (headers: dict<string>): t =>
  next =>
    async ctx =>
      (await next(ctx))->Respond.withHeaders(responseHeaders =>
        headers->Dict.forEachWithKey((value, name) =>
          if !(responseHeaders->Headers.has(name)) {
            responseHeaders->Headers.set(~name, ~value)
          }
        )
      )

@val @scope("performance") external now: unit => float = "now"

/** Logs a line per request once it's answered, like `GET /hello?name=Ada 200 3ms`. */
let logger = (~log: string => unit=Console.log): t =>
  next =>
    async ctx => {
      let start = now()
      let response = await next(ctx)
      let elapsed = (now() -. start)->Math.round->Float.toInt
      log(
        `${ctx.method->Method.toString} ${ctx.url.pathname}${ctx.url.search} ${response.status->Int.toString} ${elapsed->Int.toString}ms`,
      )
      response
    }

/** Answers with `onError`'s response if the wrapped handler throws or its promise rejects. */
let recover = (onError: (exn, RequestContext.t) => promise<Response.t>): t =>
  next =>
    async ctx =>
      try await next(ctx) catch {
      | error => await onError(error, ctx)
      }
