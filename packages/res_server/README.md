# @e-cline/res_server

A small ReScript framework for HTTP servers, built on the Web-standard
[`Request`](https://developer.mozilla.org/docs/Web/API/Request) and
[`Response`](https://developer.mozilla.org/docs/Web/API/Response) (bound by
[`@rescript/webapi`](https://rescript-lang.github.io/experimental-rescript-webapi/)).

An application is a function from a `Request` to a promise of a `Response`, so it runs anywhere that
interface does. `NodeServer` runs one on Node with
[`@hono/node-server`](https://github.com/honojs/node-server).

```rescript
open ResServer

let server =
  NodeServer.run(~port=3000)
  ->App.use(Middleware.logger())
  ->App.router([
    Route.get(list{}, async _ctx => Respond.html(Html.html`<h1>Hello</h1>`)),
    Route.get(list{"hello", ":name"}, async ctx =>
      Respond.text(`Hello, ${ctx->RequestContext.paramOrThrow("name")}!`)
    ),
    Route.get(list{"search"}, async ctx => {
      let page = ctx.query->Query.getInt("page")->Option.getOr(1)
      Respond.json(JSON.Encode.object(dict{"page": JSON.Encode.int(page)}))
    }),
  ])
```

[`examples/res_http_server`](../../examples/res_http_server) is a complete server using all of it.

## Using it

List `@e-cline/res_server` and `@rescript/webapi` in the `dependencies` of both `package.json` and
`rescript.json`. The modules are under the `ResServer` namespace. `@rescript/webapi`'s (`Request`,
`Response`, `Headers`, ...) are global; none of this package's modules share a name with them, so
`open ResServer` is safe.

`@rescript/webapi` is still experimental and has no stable release, so this package depends on one
exact version of it (`0.1.0-experimental-0781ac8`). Install that same version, or the two copies'
types won't line up.

## The pieces

Three types, and a few ways of putting them together. This is the design of
[Dream](https://camlworks.github.io/dream/#algebra).

| Type           | What it is                                | Combined with                                 |
| -------------- | ----------------------------------------- | --------------------------------------------- |
| `Handler.t`    | `RequestContext.t => promise<Response.t>` | The thing everything else is built from       |
| `Middleware.t` | `Handler.t => Handler.t`                  | One inside another: `Middleware.pipeline`     |
| `Route.t`      | A handler for some methods and paths      | As alternatives: `Router.make`, `Route.scope` |

- **A handler** answers a request. Anything of that type will do: a function you wrote, a router, or
  either of those wrapped in middleware.
- **A middleware** turns a handler into another handler. `Middleware.none` does nothing, and
  `Middleware.pipeline` joins a list of them into one, the first outermost.
- **A route** is a handler that only takes some requests. `Router.make` turns a list of routes into
  a handler that gives each request to the first route that matches. `Route.none` matches nothing,
  and `Route.scope` puts a path prefix and some middleware on several routes at once.

An application is put together from the outside in, as one pipe. It starts with what will be done
with the finished handler, then each middleware in turn, and ends with the handler they all go
around, usually a router:

```rescript
NodeServer.run(~port=3000)                              // serve the result
->App.use(Middleware.logger())                          // outermost: sees each request first
->App.use(Cors.middleware(~origins=Only([origin])))
->App.use(Middleware.provide(poolKey, pool))            // innermost middleware
->App.router([
  Route.get(list{}, home),
  Route.get(list{"users", ":id"}, showUser),
])
```

So the pipe reads in the order a request travels: through `logger`, then `Cors.middleware`, then
`provide`, into the router, and the response comes back out the same way. Each `App.use` adds its
middleware inside the ones above it.

| Step                           | What it does                                              |
| ------------------------------ | --------------------------------------------------------- |
| `NodeServer.run(~port=?, ...)` | Starts a pipe that ends with a running server             |
| `App.build(~onError=?)`        | Starts a pipe that ends with an `App.t`, to serve or test |
| `->App.use(middleware)`        | Adds a middleware, inside those already added             |
| `->App.router(routes)`         | Finishes, with a router for the routes                    |
| `->App.handle(handler)`        | Finishes, with any handler                                |

## Routing

A route is a method, a path and a handler. The path is a list with an entry per segment:

| Entry     | Matches                                                        |
| --------- | -------------------------------------------------------------- |
| `"users"` | That segment                                                   |
| `":id"`   | Any one segment, which the handler reads as the parameter `id` |
| `"**"`    | Whatever is left, including nothing. Only as the last entry    |

```rescript
let handler = Router.make([
  Route.get(list{}, home),                            // GET /
  Route.get(list{"users"}, listUsers),                // GET /users
  Route.post(list{"users"}, createUser),              // POST /users
  Route.get(list{"users", ":id"}, showUser),          // GET /users/42
  Route.any(list{"static", "**"}, serveFile),         // any method, /static/css/site.css
])
```

- There is a function per method (`get`, `post`, `put`, `patch`, `delete`, `head`, `options`), `any`
  for all of them, and `Route.method(method, path, handler)` for anything else.
- Routes are tried in order and the first match wins, so put `list{"users", "new"}` before
  `list{"users", ":id"}`.
- Trailing and repeated slashes are ignored, and segments are percent-decoded, so a parameter's
  value is already decoded.
- A request is refused with a 400 if any segment of its path, once decoded, is `.` or `..` or
  contains a slash, a backslash or a control character. Those can only arrive percent-encoded
  (`/static/..%2F..%2Fetc%2Fpasswd`), and exist to become something else when segments are joined
  into a file path. So a segment a handler is given, in `ctx.path` or as a parameter, is always one
  plain name. (`RequestContext.isSegmentSafe` is the test.)
- A `GET` route also answers `HEAD` requests: its handler runs, and the response goes out without
  its body. Add a `Route.head` for a path to answer them some other way.
- A request to a path no route has gets a plain 404. One to a path a route has, with a method none
  of them takes, gets a 405 Method Not Allowed, with an `Allow` header listing the methods that
  would work; an `OPTIONS` request gets a 204 with the same header. To answer any of those yourself,
  end with `Route.any(list{"**"}, notFound)`.
- A path that could never work (a `"**"` that isn't last, a repeated parameter name, a `/` inside an
  entry) throws when the route is declared, so it shows up at startup.

For a literal segment that looks like one of the special ones, as in `/users/:me`, wrap it:
`list{"users", Route.literal(":me")}`.

`RequestContext.param(ctx, "id")` is a parameter as an `option`, and
`RequestContext.paramOrThrow(ctx, "id")` is the parameter itself, for a handler only ever reached
through a route that has it.

### Scopes

`Route.scope(prefix, middlewares, routes)` is those routes under a path prefix, each wrapped in the
middleware. The middleware run for requests to a path one of the routes has: when a route matches,
and also around the 405 or `OPTIONS` answer for a method none of them takes. So a middleware that
answers `OPTIONS` requests itself, as `Cors.middleware` does for preflights, works on a scope.

```rescript
Router.make([
  Route.get(list{}, home),
  Route.scope(list{"admin"}, [requireAdmin], [
    Route.get(list{"users"}, listUsers),              // GET /admin/users
    Route.delete(list{"users", ":id"}, deleteUser),   // DELETE /admin/users/42
  ]),
  Env.isDev ? Route.get(list{"debug"}, debug) : Route.none,
])
```

Scopes nest, and they distribute: scoping a group of routes is the same as scoping each one, and a
scope inside a scope is one scope with both prefixes and both lists of middleware.

### Routers inside routers, and matching by hand

A router is a handler, so it can be the handler of a route. Give that route a `"**"`, and the inner
router matches against what the `"**"` matched:

```rescript
Route.any(list{"api", ":version", "**"}, Router.make(apiRoutes))
```

The inner router is an ordinary handler to the outer one, so its answer is final: if none of its
routes match, its 404 is the response, and the outer router's later routes aren't tried. For routes
that share a prefix but should be tried along with the rest, use `Route.scope`. The inner router's
handlers see the parameters the outer route bound, and one of its own with the same name takes that
name over.

That works because `ctx.path` is always the part of the path not yet routed: all of it for a handler
used directly, and whatever the route's `"**"` matched (nothing, if it has none) for a handler
behind a router. A handler can pattern-match on it too, which is sometimes the clearest way to write
a small group of routes, or the only way when their shape isn't a fixed pattern:

```rescript
let files: Handler.t = async ctx =>
  switch (ctx.method, ctx.path) {
  | (GET, list{}) => listFiles()
  | (GET, list{dir, file}) => showFile(dir, file)
  | _ => Respond.notFound()
  }

Route.any(list{"files", "**"}, files)
```

## The request: `RequestContext`

| Field     | What it is                                                   |
| --------- | ------------------------------------------------------------ |
| `method`  | A `Method.t`: `GET`, `POST`, ..., or `Other(string)`         |
| `path`    | The part of the path not yet routed, as decoded segments     |
| `params`  | The path parameters the route bound, a `Map` (see "Routing") |
| `query`   | The query string, a `Query.t`                                |
| `url`     | The parsed Web `URL`                                         |
| `request` | The Web `Request` itself                                     |
| `context` | What middleware have attached (see "Middleware and context") |

`RequestContext.header(ctx, name)` reads a request header, and `RequestContext.cookie(ctx, name)` a
cookie. Anything keyed by a name the client chose comes as a `Map`, not a `dict`: `params`,
`RequestContext.cookies`, `Query.toMap`, `HttpHeaders.toMap`. Use one for your own lookups by
client-supplied keys too, such as API tokens: a `dict` is a JavaScript object, where
`dict->Dict.get("constructor")` finds something that was never put there.
`RequestContext.bearerToken(ctx)` is the token of an `Authorization: Bearer ...` header.

The body is read with `RequestContext.text`, `RequestContext.json` or `RequestContext.form` (a
URL-encoded form, as a `Query.t`). A body can be read once; reading it again throws. The last two
return a `result`, whose error says what was wrong:

- `WrongContentType`: the request didn't declare the body as that kind. `json` wants
  `application/json` (or a type ending `+json`), and `form` wants
  `application/x-www-form-urlencoded`. This is more than tidiness: a page on another site can make a
  visitor's browser send a `text/plain` or form body here, with their cookies, without asking, but
  not a JSON one. Insisting on the type is part of what stops other sites submitting JSON as your
  visitors. `json(~anyContentType=true)` parses the body whatever it claims to be.
- `Malformed(message)`: it was the right kind, and isn't valid.

Those are usually a 415 and a 400. `RequestContext.bodyErrorMessage` turns either into a sentence
for the client.

### Query parameters: `Query`

A read-only wrapper over `URLSearchParams` with getters that return `option`s:

- `get`, `getAll`, `getOr` and `has`, for strings.
- `getInt`, `getFloat` and `getBool`, which are `None` when the value is missing _or_ isn't one:
  `?page=2x` is not page 2.
- `toArray`, `toMap` and `toString`.

A name that appears more than once (`?tag=a&tag=b`) gives its first value to the single-value
getters and all of them to `getAll`.

## Responses: `Respond`

Each takes an optional `~status` and extra `~headers`, and sets the `content-type`.

| Function                             | Sends                                                      |
| ------------------------------------ | ---------------------------------------------------------- |
| `text(string)`                       | `text/plain`                                               |
| `html(Html.t)`                       | `text/html`                                                |
| `json(JSON.t)`                       | `application/json`                                         |
| `ndjson(next)`                       | A stream of JSON values, one per line                      |
| `textStream(next)`                   | A stream of text chunks                                    |
| `stream(~contentType, ByteStream.t)` | Any stream of bytes                                        |
| `redirect(location)`                 | A 302 (or other `~status`) to a URL, which may be relative |
| `empty()`                            | No body; 204 by default                                    |
| `notFound()`                         | A plain-text 404                                           |

`Respond.withHeader(response, name, value)` sets a header on a response afterwards. It and the other
functions that change a response's headers work on any `Response`, including one from `fetch`, whose
headers are read-only: those are copied first.

### Cookies

```rescript
let login = async ctx => {
  let session = await createSession(ctx)
  Respond.redirect("/")->Respond.setCookie("session", session, ~options={maxAge: 86400, secure: true})
}

let logout = _ctx => Respond.redirect("/")->Respond.deleteCookie("session")

let whoami = ctx =>
  switch ctx->RequestContext.cookie("session") {
  | Some(session) => showUser(session)
  | None => Respond.text(~status=401, "Not logged in")
  }
```

`Respond.setCookie` adds a `Set-Cookie` header, so call it once per cookie. The defaults are the
cautious ones:

| Option        | Default | Meaning                                                                              |
| ------------- | ------- | ------------------------------------------------------------------------------------ |
| `path`        | `/`     | Which paths the cookie is sent to                                                    |
| `domain`      | unset   | Unset: only the host that set it. Set: that domain and its subdomains                |
| `maxAge`      | unset   | Lifetime in seconds. Unset (with no `expires`): until the browser closes             |
| `expires`     | unset   | An expiry date                                                                       |
| `httpOnly`    | `true`  | Scripts in the page can't read the cookie                                            |
| `secure`      | `false` | Only sent over HTTPS. Off so that `http://localhost` works; turn it on in production |
| `sameSite`    | `Lax`   | `Strict`, `Lax`, or `CrossSite` (`SameSite=None`)                                    |
| `partitioned` | `false` | A separate cookie per top-level site                                                 |

A cookie's value can be any string: it's percent-encoded when set and decoded when read. Its name
and its `path` and `domain` can't, since they're written into the header as they are, so `setCookie`
throws if one of them contains something that could add an attribute of its own. Cookies aren't
signed or encrypted; don't trust what one says beyond an unguessable identifier you look up.

`Secure` is added, whatever `secure` says, wherever a browser would drop the cookie without it: for
`sameSite: CrossSite`, for `partitioned`, and for a name starting `__Host-` or `__Secure-`. A
`__Host-` name with a `domain` or a `path` other than `/` throws, since that prefix rules them out.
`Respond.deleteCookie` follows the same rules, and takes `~partitioned` for a cookie that was set
with it.

`Cookie.parse` and `Cookie.serialize` are the functions underneath.

### HTML

`Respond.html` takes an `Html.t`, not a string. One can only be made from escaped text
(`Html.text`), other `Html.t` values, or a string you explicitly vouch for (`Html.raw`), so a value
from a request can't reach a page unescaped by accident. The `Html.html` tagged template writes
markup around them:

```rescript
let page = (~title, ~items) =>
  Html.html`<h1>${Html.text(title)}</h1>
<ul>${items->Array.map(item => Html.html`<li>${Html.text(item)}</li>`)->Html.join}</ul>`
```

`Html.text` is right between tags and inside a quoted attribute value. Two places need something
else, because escaping isn't what makes them safe:

- **A URL attribute** (`href`, `src`): `javascript:alert(1)` has nothing in it to escape. `Html.url`
  lets through `http:`, `https:`, `mailto:` and `tel:` URLs and relative ones, and turns anything
  else into `about:invalid`.
- **Inside a `<script>`**: HTML escaping doesn't apply there, and what matters is not containing
  `</script>`. `Html.json` writes a JSON value so that it can't.

```rescript
Html.html`<a href="${Html.url(user.website)}">${Html.text(user.name)}</a>
<script type="application/json" id="user">${Html.json(userJson)}</script>`
```

### Streaming

`ndjson` and `textStream` take a function, `next`, returning a promise of the next value, or `None`
to end the response. It's called for one value at a time and only when the client is ready for more,
so a slow client slows the producer down instead of filling memory; and it's not called again once
the client disconnects.

```rescript
let countdown = from => {
  let remaining = ref(from)
  Respond.ndjson(async () =>
    if remaining.contents < 0 {
      None
    } else {
      let value = remaining.contents
      remaining := value - 1
      Some(JSON.Encode.int(value))
    }
  )
}
```

Both take an `~onEnd`, called once when the response is over, however that happens: `Completed` (all
of it was sent), `Cancelled` (the client went away) or `Failed(error)` (`next` threw). It's where to
release whatever `next` was reading from:

```rescript
let export = async _ctx => {
  let cursor = await openCursor()
  Respond.ndjson(~onEnd=_ending => cursor->Cursor.close, () => cursor->Cursor.next)
}
```

`ByteStream` has the bindings underneath: a typed `ReadableStream` of bytes, its underlying source
and reader, and `TextEncoder`/`TextDecoder`.

## Middleware and context

A `Middleware.t` is a function from a handler to a handler. Given the handler it wraps (`next`), it
returns one that can answer by itself, call `next`, and change the response on the way out:

```rescript
let timing: Middleware.t = next =>
  async ctx => {
    let start = Date.now()
    let response = await next(ctx)
    response->Respond.withHeader("server-timing", `app;dur=${(Date.now() -. start)->Float.toString}`)
  }
```

One that takes settings is a function returning a middleware:
`let requireRole = (role: string): Middleware.t => next => async ctx => ...`.

A middleware goes around:

- the whole application, with `->App.use(timing)`;
- a group of routes, with `Route.scope(prefix, [timing], routes)`;
- one handler, with `timing->Middleware.apply(handler)`, as in
  `Route.delete(path, requireUser->Middleware.apply(deleteAccount))`.

Wherever several are given, the first is the outermost. The ones that come with the framework:

| Middleware                         | What it does                                   |
| ---------------------------------- | ---------------------------------------------- |
| `Middleware.logger(~log=?)`        | Logs a line per request                        |
| `Middleware.provide(key, value)`   | Attaches a value to every request (below)      |
| `Middleware.responseHeaders(dict)` | Adds headers to every response that lacks them |
| `Middleware.recover(onError)`      | Answers for a handler that throws              |
| `Cors.middleware(~origins, ...)`   | CORS (below)                                   |

To combine them:

- `Middleware.pipeline([a, b, c])` is one middleware, with `a` outermost.
- `Middleware.none` does nothing. It's for a middleware that is only wanted some of the time:

  ```rescript
  App.build()
  ->App.use(verbose ? Middleware.logger() : Middleware.none)
  ->App.router(routes)
  ```

### Attaching values to a request: `Context`

A middleware often works something out that the handlers behind it need: who the user is, a database
connection, the application's configuration. It attaches it to the request under a typed _key_, and
they read it back with the same key. This follows [Dream](https://camlworks.github.io/dream/)'s
design.

```rescript
// A key for a `User.t`. Made once, by whichever module owns the value.
let userKey: Context.Key.t<User.t> = Context.Key.make(~name="user")

let requireUser: Middleware.t = next =>
  async ctx =>
    switch await findUser(ctx) {
    | Some(user) => await next(ctx->RequestContext.set(userKey, user))
    | None => Respond.text(~status=401, "Unauthorized")
    }

let currentUser = (ctx: RequestContext.t): User.t => ctx->RequestContext.getOrThrow(userKey)
```

- `Context.Key.make(~name)` makes a key. The name is required; it's what error messages call the
  value.
- `RequestContext.set(ctx, key, value)` returns a new request context with the value attached. They
  are immutable, so a middleware attaches something by passing the result to `next`.
- `RequestContext.get(ctx, key)` is the value as an `option`.
- `RequestContext.getOrThrow(ctx, key)` is the value, for code that can't do anything without it. It
  throws, naming the key, if the middleware that sets it wasn't applied to the route.
- `Middleware.provide(key, value)` is a middleware that attaches the same value to every request:
  how handlers get at something the whole application shares.

  ```rescript
  let poolKey: Context.Key.t<Db.pool> = Context.Key.make(~name="db pool")

  let app = App.build()->App.use(Middleware.provide(poolKey, pool))->App.router(routes)
  ```

The values live in a `Context.t`, which the request carries as `ctx.context`. `Context.get` and
`Context.set` work on one directly, and `Context.empty` is one with nothing in it.

A key is the only way to its value, and carries the value's type, so this is type-safe: what `get`
returns is what the key says, and setting anything else doesn't compile. Because the request context
has one type however many keys are in use, middleware from separate modules compose without knowing
about each other, and adding one changes no handler's type. A module can keep its key private and
export only a middleware and an accessor, as Dream's `sql_pool` and `sql` do.

What the types don't check is that a value has been _set_: a handler that needs a user can be routed
to without `requireUser`, and finds out when it runs. `get` makes that case explicit as `None`;
`getOrThrow` turns it into an error (so a 500, by default) with a message that says which key was
missing.

### CORS

`Cors.middleware` tells browsers which other sites' pages may call the server:

```rescript
let app =
  App.build()
  ->App.use(Cors.middleware(~origins=Only(["https://app.example"]), ~credentials=true, ~maxAge=600))
  ->App.router(routes)
```

`~origins` is required, and is `Any`, `Only([...])` (compared exactly: scheme, host and port, no
trailing slash) or `Where(origin => bool)`. The rest is optional: `~methods`, `~allowHeaders`
(default: whatever the browser asks to send), `~exposeHeaders`, `~credentials` and `~maxAge`.

- Preflight requests are answered by the middleware and don't reach the handler.
- `~credentials=true` with origins that let everyone in throws when the middleware is made, which is
  when the application is set up: it would let any site act as a visitor who is logged in here. That
  means `Any`, and an `Only` or `Where` that allows the origin `null` or one that belongs to nobody,
  which is how a `Where` that says yes to everything is caught.
- With `~origins=Any` every response is marked, whether or not the request named an origin, so a
  cached one is still usable from another site.
- It works around the whole application or on a `Route.scope`.
- CORS isn't access control. A request from an origin that isn't allowed still reaches the handler;
  the browser just won't let that page read the answer. Authenticate requests as usual.

## Errors

If a handler throws, or its promise rejects, the application answers with its `~onError` function's
response: by default a plain 500, after logging the error. (If `onError` itself throws, the answer
is that plain 500 too.) Nothing about the error is sent to the client unless `onError` sends it.
`App.build`, `App.make` and `NodeServer.run` all take it.

```rescript
let app =
  App.build(~onError=(error, _request) => {
    Console.error(error)
    Respond.text(~status=500, "Something went wrong")
  })
  ->App.use(Middleware.logger())
  ->App.router(routes)
```

In an application made with `App.build` or `NodeServer.run`, that happens inside the middleware,
right around the handler. So to the middleware the 500 is a response like any other: `logger` logs
it, `Cors.middleware` marks it, `responseHeaders` adds to it. The same goes for the 400 given to a
request with an unsafe path.

An error thrown by a middleware itself has nothing around it but the application, so it gets
`onError`'s response as it is, without passing through the other middleware. To handle errors at
some particular point instead, error handling is also a middleware:
`Middleware.recover(async (error, ctx) => ...)` answers for whatever is inside it, and can go
anywhere in the pipe, or on one `Route.scope`.

## Running

`NodeServer.run` starts a pipe that ends with a running server, as at the top of this page. Its
`~port` defaults to 3000, and `~onListen` is called once it's accepting connections.

It listens on `127.0.0.1` by default, so only this machine can reach it. A deployed server, or one
in a container, has to accept connections from elsewhere: pass `~hostname="0.0.0.0"`.

To have the application as a value instead, to test it or to serve it some other way, start the pipe
with `App.build`. The result is an `App.t`, which is just `Request.t => promise<Response.t>`: a
standard fetch handler. (`App.make(handler)` makes one from a handler directly.)

```rescript
let app = App.build()->App.use(Middleware.logger())->App.router(routes)

let server = app->NodeServer.serve(~port=3000, ~onListen=address =>
  Console.log(`Listening on port ${address.port->Int.toString}`)
)
```

`NodeServer.listen` is `serve` as a promise of the server and its address, and `NodeServer.close`
stops one. Port 0 picks a free port, which is how this package's own tests run a real server.

If the server can't listen, most often because the port is in use, `listen`'s promise is rejected.
`serve` and `run` take an `~onServerError` for it; without one the error is thrown, which ends the
process.

From JavaScript or TypeScript, pass the compiled export to anything that takes a fetch handler:

```js
import {serve} from '@hono/node-server';

import {app} from './src/Routes.res.jsx';

serve({fetch: app, port: 3000});
```

In tests there's no need for a server at all: call the app with a `Request`.

## Layout

- `App.res` -- turns a handler into a fetch handler, with error handling.
- `RequestContext.res`, `Method.res`, `Query.res`, `HttpHeaders.res` -- the request.
- `Handler.res`, `Middleware.res`, `Route.res`, `Router.res` -- the three types and how they
  combine.
- `Context.res` -- typed keys for attaching values to a request.
- `Respond.res`, `Html.res`, `ByteStream.res` -- responses.
- `Cookie.res`, `Cors.res` -- cookies, and the CORS middleware.
- `NodeServer.res` -- bindings to `@hono/node-server`.
- `tests/` -- `*_test.res` tests and the test-only `TestSupport.res`. `NodeServer_test.res` runs a
  server and calls it over HTTP, and `TypeSafety_test.res` gives the compiler programs that misuse
  the API and checks that it refuses them. They're a `"type": "dev"` source directory, so a project
  that depends on this package doesn't compile them, or need `rescript-vitest`.

```bash
pnpm --filter @e-cline/res_server exec vp run test
```

## Not included

No sessions, signed cookies, static files, body size limits or multipart parsing.
`RequestContext.request` is the Web `Request`, so anything it can do is still available.
