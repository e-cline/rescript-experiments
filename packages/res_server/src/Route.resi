/***
Routes: which handler answers which requests.

A route pairs a method and a path with a handler. The path is a list of
segments, each one of:

- a literal segment, like `"users"`, which matches only itself;
- `":name"`, which matches any one segment and gives it to the handler as the
  parameter `name` (see `RequestContext.param`);
- `"**"`, which matches whatever is left, including nothing. It can only come
  last. The handler finds the rest of the path in `ctx.path`.

For a literal segment that looks like one of the other two, as in a path like
`/users/:me`, use `literal`: `list{"users", Route.literal(":me")}`.

```rescript
Route.get(list{}, home)                         // GET /
Route.get(list{"users", ":id"}, showUser)       // GET /users/42
Route.any(list{"static", "**"}, serveFile)      // any method, /static/css/site.css
```

Routes are alternatives: a `Router` tries them in order and uses the first
that matches. `none` matches nothing, and `scope` puts a path prefix and some
middleware on a group of routes at once.
*/

type t

/**
A path entry that matches exactly `segment`, even if it starts with `:` or is
`**`. (It is `segment` after a backslash, which is what marks an entry as
literal.)
*/
let literal: string => string

/** A route for GET requests to `path`. */
let get: (list<string>, Handler.t) => t

let post: (list<string>, Handler.t) => t

let put: (list<string>, Handler.t) => t

let patch: (list<string>, Handler.t) => t

let delete: (list<string>, Handler.t) => t

let head: (list<string>, Handler.t) => t

let options: (list<string>, Handler.t) => t

/** A route for requests to `path` with any method. */
let any: (list<string>, Handler.t) => t

/** A route for requests to `path` with the given method. */
let method: (Method.t, list<string>, Handler.t) => t

/**
The route that matches nothing. For when a route is wanted only some of the
time:

```rescript
let debugRoutes = Env.isDev ? Route.get(list{"debug"}, debug) : Route.none
```
*/
let none: t

/**
The given routes under a path prefix, each with the given middleware (the
first outermost). The prefix may have `":name"` segments.

The middleware run for requests to a path one of the routes has. That's
normally because the route matched, but it includes a request with a method
none of them takes, which a `Router` answers itself (see `mismatch`): so a
middleware here that answers `OPTIONS` requests, like `Cors.middleware`, gets
them.

```rescript
Route.scope(list{"admin"}, [requireAdmin], [
  Route.get(list{"users"}, listUsers),          // GET /admin/users
  Route.delete(list{"users", ":id"}, deleteUser),
])
```

Scoping a group of routes is the same as scoping each one:
`scope(p, m, [a, b])` matches exactly what `scope(p, m, [a])` followed by
`scope(p, m, [b])` does. So does nesting: `scope(p, m, [scope(q, n, routes)])`
is `scope(p ++ q, m ++ n, routes)`.
*/
let scope: (list<string>, array<Middleware.t>, array<t>) => t

/**
Tries a route: the response of its handler if it matches the request's method
and `ctx.path`, and `None` if it doesn't. The handler sees the parameters the
path bound, and as `ctx.path` whatever a `"**"` matched (nothing, without one).

A `HEAD` request is taken by a `GET` route if no route asks for `HEAD`
itself. Its handler runs as usual, and the response is sent without its body.
*/
let handle: (t, RequestContext.t) => option<promise<Response.t>>

/**
An answer for a request that the route has the path for, but not the method:
`None` if no route with a method has that path.

- An `OPTIONS` request gets a 204 with an `Allow` header listing the methods
  the path takes.
- Any other gets a 405 Method Not Allowed, with the same header.

The answer is made inside the middleware of the first route with that path.
A `Router` uses this for requests `handle` turns down.
*/
let mismatch: (t, RequestContext.t) => option<promise<Response.t>>
