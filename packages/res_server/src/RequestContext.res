/***
What a handler is given: the request, already taken apart for routing, plus
whatever middleware have attached to it (see `get` and `set` below).

Which handler a request reaches is normally decided by a `Router`. A handler
can also look at the request itself: `path` is the URL's path as a list of
decoded segments, so `/users/42/` is `list{"users", "42"}` and `/` is
`list{}`, and can be pattern-matched together with `method`:

```rescript
switch (ctx.method, ctx.path) {
| (GET, list{"users", id}) => showUser(id)
| (POST, list{"users"}) => createUser(ctx)
| _ => Respond.notFound()
}
```
*/

type t = {
  /** The Web `Request` this was made from. */
  request: Request.t,
  method: Method.t,
  url: UrlTypes.url,
  /**
  The part of the path that hasn't been routed yet, as decoded segments: all
  of it to begin with, and inside a route, whatever its `"**"` matched.
  */
  path: list<string>,
  /** The path parameters bound by the route that matched (see `param`). */
  params: Map.t<string, string>,
  query: Query.t,
  /** What's been attached to the request. Read and written with `get` and `set`. */
  context: Context.t,
}

@val external decodeURIComponent: string => string = "decodeURIComponent"

/**
Splits a URL path into decoded segments, ignoring empty ones. A segment that
isn't valid percent-encoding is kept as it is.
*/
let pathSegments = (pathname: string): list<string> =>
  pathname
  ->String.split("/")
  ->Array.filter(segment => segment != "")
  ->Array.map(segment =>
    try decodeURIComponent(segment) catch {
    | _ => segment
    }
  )
  ->List.fromArray

/**
Whether a decoded segment is safe to treat as one name in a path. It isn't if
it is `.` or `..`, or contains a slash, a backslash or a control character: all things
that can only get into a segment percent-encoded (`..%2F..%2Fetc`), and that
turn into something else as soon as segments are joined into a file path.
*/
let isSegmentSafe = (segment: string): bool =>
  segment != "." && segment != ".." && !(/[\/\\\x00-\x1f\x7f]/->RegExp.test(segment))

let make = (request: Request.t): t => {
  let url = URL.make(~url=request.url)
  {
    request,
    method: Method.fromString(request.method),
    url,
    path: pathSegments(url.pathname),
    params: Map.make(),
    query: Query.fromSearchParams(url.searchParams),
    context: Context.empty,
  }
}

/**
The value attached to the request under `key`, if there is one.

```rescript
let currentUser = ctx => ctx->RequestContext.get(userKey)
```
*/
let get = (ctx: t, key: Context.Key.t<'a>): option<'a> => ctx.context->Context.get(key)

/**
The same request with `value` attached under `key`, replacing any value
already there. Requests are immutable, so this returns a new one: a
middleware attaches something by passing the result on.

```rescript
let authenticate: Middleware.t = next =>
  async ctx =>
    switch await findUser(ctx) {
    | Some(user) => await next(ctx->RequestContext.set(userKey, user))
    | None => Respond.text(~status=401, "Unauthorized")
    }
```
*/
let set = (ctx: t, key: Context.Key.t<'a>, value: 'a): t => {
  ...ctx,
  context: ctx.context->Context.set(key, value),
}

/**
The value attached under `key`, for code that can't do anything without
it. Throws if there isn't one, naming the key, which means the middleware
that attaches it wasn't applied to this route: a mistake in how the
application is put together, not something a request can cause.
*/
let getOrThrow = (ctx: t, key: Context.Key.t<'a>): 'a =>
  switch ctx->get(key) {
  | Some(value) => value
  | None =>
    JsError.throwWithMessage(
      `No "${key->Context.Key.name}" in this request's context. Is the middleware that sets it applied to this route?`,
    )
  }

/**
Whether every segment of the request's path is safe (see `isSegmentSafe`).
`App` answers 400 to requests whose path isn't, so a handler reached through
one never sees such a segment, in `ctx.path` or as a parameter.
*/
let isPathSafe = (ctx: t): bool => pathSegments(ctx.url.pathname)->List.every(isSegmentSafe)

/** The same request with a different `path`. */
let withPath = (ctx: t, path: list<string>): t => {...ctx, path}

/**
A path parameter: what the segment `":name"` in the route's path matched,
decoded. `None` if the route that matched has no parameter of that name.
*/
let param = (ctx: t, name: string): option<string> => ctx.params->Map.get(name)

/**
A path parameter, for a handler that is only ever reached through a route
that has it. Throws if there isn't one, which means the name here and the one
in the route's path don't agree.
*/
let paramOrThrow = (ctx: t, name: string): string =>
  switch ctx->param(name) {
  | Some(value) => value
  | None =>
    JsError.throwWithMessage(
      `No path parameter "${name}" for this request. Does the route's path have a ":${name}" segment?`,
    )
  }

/** A request header, by case-insensitive name. */
let header = (ctx: t, name: string): option<string> => ctx.request.headers->HttpHeaders.get(name)

/** The request's cookies, by name. */
let cookies = (ctx: t): Map.t<string, string> =>
  ctx->header("cookie")->Option.mapOr(Map.make(), Cookie.parse)

/** A cookie the request was sent with. */
let cookie = (ctx: t, name: string): option<string> => ctx->cookies->Map.get(name)

/** The request body as text. A body can only be read once. */
let text = (ctx: t): promise<string> => ctx.request->Request.text

/**
The request's media type: its `Content-Type` in lower case, without
parameters such as `charset`. `None` if it has none.
*/
let contentType = (ctx: t): option<string> =>
  ctx
  ->header("content-type")
  ->Option.flatMap(value => value->String.split(";")->Array.get(0))
  ->Option.map(value => value->String.trim->String.toLowerCase)
  ->Option.filter(value => value != "")

/**
The token of an `Authorization: Bearer <token>` header. The scheme is matched
whatever its case, as the specification has it. `None` if the header is
missing, has another scheme, or has no token.
*/
let bearerToken = (ctx: t): option<string> =>
  ctx
  ->header("authorization")
  ->Option.flatMap(value => {
    let value = value->String.trim
    switch value->String.indexOf(" ") {
    | -1 => None
    | index =>
      let scheme = value->String.slice(~start=0, ~end=index)
      let token = value->String.slice(~start=index + 1)->String.trim
      scheme->String.toLowerCase == "bearer" && token != "" ? Some(token) : None
    }
  })

/** Why a request's body couldn't be used. */
type bodyError =
  /**
  The body isn't declared as the kind asked for: `actual` is the request's
  media type, if it gave one. Usually answered with a 415.
  */
  | WrongContentType({expected: string, actual: option<string>})
  /** The body is the right kind, but isn't valid. Usually answered with a 400. */
  | Malformed(string)

/** A sentence describing a `bodyError`, fit to send to the client. */
let bodyErrorMessage = (error: bodyError): string =>
  switch error {
  | WrongContentType({expected, actual: Some(actual)}) =>
    `Expected a body of type ${expected}, not ${actual}`
  | WrongContentType({expected, actual: None}) =>
    `Expected a body of type ${expected}, with a Content-Type header saying so`
  | Malformed(message) => message
  }

/**
The request body parsed as JSON.

The request has to say that's what it is, with a `Content-Type` of
`application/json` (or one ending `+json`). That matters beyond tidiness: a
page on another site can make a visitor's browser send a `text/plain` or form
body here without asking, but not a JSON one, so insisting on the type is part
of what stops other sites submitting JSON on a visitor's behalf. Pass
`~anyContentType=true` to parse the body whatever it claims to be.

Failing to read the body at all, as when it has been read already, is not an
`Error`: it's thrown, like any other mistake in the program.
*/
let json = async (~anyContentType: bool=false, ctx: t): result<JSON.t, bodyError> => {
  let actual = ctx->contentType
  let isJson = switch actual {
  | Some(mediaType) => mediaType == "application/json" || mediaType->String.endsWith("+json")
  | None => false
  }
  if anyContentType || isJson {
    let body = await ctx->text
    switch JSON.parseOrThrow(body) {
    | json => Ok(json)
    | exception JsExn(error) => Error(Malformed(error->JsExn.message->Option.getOr("Invalid JSON")))
    }
  } else {
    Error(WrongContentType({expected: "application/json", actual}))
  }
}

/**
The request body as the fields of a URL-encoded form, which is what an HTML
form sends unless it uploads files. An `Error` if the request's `Content-Type`
isn't `application/x-www-form-urlencoded`: a `multipart/form-data` body, say,
would otherwise be read as one long, meaningless field.
*/
let form = async (ctx: t): result<Query.t, bodyError> => {
  let expected = "application/x-www-form-urlencoded"
  switch ctx->contentType {
  | Some(actual) if actual == expected => Ok(Query.fromString(await ctx->text))
  | actual => Error(WrongContentType({expected, actual}))
  }
}
