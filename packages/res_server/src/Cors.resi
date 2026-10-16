/***
[Cross-Origin Resource Sharing](https://developer.mozilla.org/docs/Web/HTTP/CORS):
a middleware that tells browsers which other sites' pages may call this server
and read its responses.

CORS relaxes a restriction that browsers enforce; it isn't access control.
A request from an origin that isn't allowed still reaches the handler -- the
browser just won't let that page read the response -- and anything that isn't
a browser ignores it entirely. Authenticate requests as usual.
*/

/** Which origins (a scheme, host and port, like `https://app.example`) are allowed. */
type origins =
  /** Any site. Not allowed together with credentials. */
  | Any
  /** These origins, exactly as the browser sends them: no trailing slash, no path. */
  | Only(array<string>)
  /** Origins this function accepts. */
  | Where(string => bool)

/**
The middleware: answers CORS preflights, and marks the responses of the
handler it wraps.

```rescript
App.build()
->App.use(Cors.middleware(~origins=Only(["https://app.example"])))
->App.router(routes)
```

- `origins`: who may call. Required: there's no safe default to guess.
- `methods`: what a cross-origin request may use. Default: `GET`, `HEAD`,
  `POST`, `PUT`, `PATCH`, `DELETE`.
- `allowHeaders`: request headers a caller may set. Default: whichever ones
  the browser asks for.
- `exposeHeaders`: response headers a calling page may read, beyond the few
  it always can.
- `credentials`: let callers send cookies and HTTP authentication, and read
  the response when they do. Default `false`.
- `maxAge`: how long, in seconds, a browser may remember the answer to a
  preflight request instead of asking again.

Preflight requests (the `OPTIONS` request a browser sends first to ask
permission) are answered here and don't reach the handler.

Throws, when called, if `credentials` is combined with origins that let
everyone in, since that would let every site on the web act as a visitor who
is logged in here: with `Any`, or with an `Only` or `Where` that allows the
origin `null` (what sandboxed pages and local files send) or one that belongs
to nobody. The second catches a `Where` that says yes to everything.

Works around a whole application (`App.use`) or a group of routes
(`Route.scope`): a scope's middleware is given the preflights for its routes'
paths.
*/
let middleware: (
  ~origins: origins,
  ~methods: array<Method.t>=?,
  ~allowHeaders: array<string>=?,
  ~exposeHeaders: array<string>=?,
  ~credentials: bool=?,
  ~maxAge: int=?,
) => Middleware.t
