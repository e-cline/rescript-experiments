type entry = {
  // `None` for any method.
  method: option<Method.t>,
  pattern: list<string>,
  // The middleware of the scopes the route is in, the outermost first. Kept
  // apart from the handler so that it can go around the answer to a request
  // for the route's path with another method, too (see `mismatch`).
  middleware: Middleware.t,
  // The route's own handler, inside `middleware`.
  handler: Handler.t,
}

// A route is the alternatives it stands for, in order: one for a route made
// by `get` and the like, none for `none`, and any number for a `scope`.
type t = array<entry>

// What an entry in a route's path stands for.
type segment =
  | Literal(string)
  | Parameter(string)
  | Rest

// A leading backslash makes the rest literal, whatever it looks like.
let parseSegment = (segment: string): segment =>
  if segment->String.startsWith("\\") {
    Literal(segment->String.slice(~start=1))
  } else if segment == "**" {
    Rest
  } else if segment->String.startsWith(":") {
    Parameter(segment->String.slice(~start=1))
  } else {
    Literal(segment)
  }

let literal = (segment: string): string => "\\" ++ segment

// Fails for a pattern that could never work as written. This runs when the
// routes are declared, so a mistake shows up at startup, not on a request.
let rec check = (~whole: list<string>, ~seen: list<string>=list{}, pattern: list<string>): unit => {
  let fail = (problem: string): unit =>
    JsError.throwWithMessage(
      `Invalid route path [${whole
        ->List.toArray
        ->Array.map(segment => JSON.stringifyAny(segment)->Option.getOr(""))
        ->Array.join(", ")}]: ${problem}`,
    )
  switch pattern {
  | list{} => ()
  | list{segment, ...rest} =>
    switch parseSegment(segment) {
    | Rest =>
      if rest != list{} {
        fail(`"**" can only be the last segment`)
      }
    | Parameter("") => fail(`":" needs a parameter name after it`)
    | Parameter(name) =>
      if seen->List.has(name, (a, b) => a == b) {
        fail(`the parameter "${name}" appears more than once`)
      }
      check(~whole, ~seen=list{name, ...seen}, rest)
    | Literal(text) =>
      if text == "" {
        fail("a segment can't be empty")
      }
      if !RequestContext.isSegmentSafe(text) {
        fail(`a segment can't be "." or "..", or contain a slash, a backslash or a control character; give each part of the path its own entry in the list`)
      }
      check(~whole, ~seen, rest)
    }
  }
}

let make = (method: option<Method.t>, pattern: list<string>, handler: Handler.t): t => {
  check(~whole=pattern, pattern)
  [{method, pattern, middleware: Middleware.none, handler}]
}

let method = (method: Method.t, path: list<string>, handler: Handler.t): t =>
  make(Some(method), path, handler)

let get = (path: list<string>, handler: Handler.t): t => make(Some(GET), path, handler)
let post = (path: list<string>, handler: Handler.t): t => make(Some(POST), path, handler)
let put = (path: list<string>, handler: Handler.t): t => make(Some(PUT), path, handler)
let patch = (path: list<string>, handler: Handler.t): t => make(Some(PATCH), path, handler)
let delete = (path: list<string>, handler: Handler.t): t => make(Some(DELETE), path, handler)
let head = (path: list<string>, handler: Handler.t): t => make(Some(HEAD), path, handler)
let options = (path: list<string>, handler: Handler.t): t => make(Some(OPTIONS), path, handler)
let any = (path: list<string>, handler: Handler.t): t => make(None, path, handler)

let none: t = []

let scope = (prefix: list<string>, middlewares: array<Middleware.t>, routes: array<t>): t => {
  let middleware = Middleware.pipeline(middlewares)
  routes
  ->Array.flat
  ->Array.map(entry => {
    let pattern = List.concat(prefix, entry.pattern)
    check(~whole=pattern, pattern)
    {
      method: entry.method,
      pattern,
      middleware: handler => middleware(entry.middleware(handler)),
      handler: middleware(entry.handler),
    }
  })
}

// The parameters a pattern binds in a path and what its `"**"` matched, or
// `None` if the path doesn't fit it.
let rec matchPath = (
  ~params: Map.t<string, string>,
  pattern: list<string>,
  path: list<string>,
): option<list<string>> =>
  switch (pattern, path) {
  | (list{}, list{}) => Some(list{})
  | (list{}, _) => None
  | (list{expected, ...pattern}, path) =>
    switch (parseSegment(expected), path) {
    | (Rest, rest) => Some(rest)
    | (Parameter(name), list{segment, ...path}) =>
      params->Map.set(name, segment)
      matchPath(~params, pattern, path)
    | (Literal(text), list{segment, ...path}) if text == segment =>
      matchPath(~params, pattern, path)
    | _ => None
    }
  }

// The request as the entry's handler should see it, if its path fits the
// entry's pattern: with the parameters the pattern bound, and whatever its
// `"**"` matched as the path.
let matchEntryPath = (entry: entry, ctx: RequestContext.t): option<RequestContext.t> => {
  // Starts from the parameters already bound, by a router this one is nested in.
  let params = Map.fromIterator(ctx.params->Map.entries)
  matchPath(~params, entry.pattern, ctx.path)->Option.map(rest => {...ctx, path: rest, params})
}

// The first entry accepted by `accepts` whose pattern fits the request's path,
// with the request as its handler should see it.
let find = (route: t, ctx: RequestContext.t, accepts: entry => bool): option<(
  entry,
  RequestContext.t,
)> => {
  let rec from = (index: int): option<(entry, RequestContext.t)> =>
    switch route->Array.get(index) {
    | None => None
    | Some(entry) =>
      switch accepts(entry) ? matchEntryPath(entry, ctx) : None {
      | Some(matched) => Some((entry, matched))
      | None => from(index + 1)
      }
    }
  from(0)
}

let handle = (route: t, ctx: RequestContext.t): option<promise<Response.t>> => {
  // A HEAD request is a GET whose answer is wanted without its body, so a
  // GET route takes it, unless there's a route for HEAD itself at that path.
  let getTakesHead =
    ctx.method == HEAD && route->find(ctx, entry => entry.method == Some(HEAD))->Option.isNone
  route
  ->find(ctx, entry =>
    switch entry.method {
    | None => true
    | Some(GET) if getTakesHead => true
    | Some(method) => method == ctx.method
    }
  )
  ->Option.map(((entry, matched)) =>
    switch (entry.method, ctx.method) {
    | (Some(GET), HEAD) => entry.handler(matched)->Promise.thenResolve(Respond.withoutBody)
    | _ => entry.handler(matched)
    }
  )
}

let mismatch = (route: t, ctx: RequestContext.t): option<promise<Response.t>> => {
  let methods = []
  let first = ref(None)
  route->Array.forEach(entry =>
    switch (entry.method, matchEntryPath(entry, ctx)) {
    | (Some(method), Some(matched)) =>
      if !(methods->Array.includes(method)) {
        methods->Array.push(method)
      }
      if first.contents->Option.isNone {
        first := Some((entry, matched))
      }
    | _ => ()
    }
  )
  first.contents->Option.map(((entry, matched)) => {
    // What a request to this path could have used: what the routes take, HEAD
    // wherever GET is, and OPTIONS, which is answered here.
    let allowed =
      [Method.GET, HEAD, POST, PUT, PATCH, DELETE]
      ->Array.filter(method =>
        methods->Array.includes(method) || (method == HEAD && methods->Array.includes(GET))
      )
      ->Array.concat(
        methods->Array.filter(method =>
          switch method {
          | Other(_) => true
          | _ => false
          }
        ),
      )
      ->Array.concat([OPTIONS])
      ->Array.map(Method.toString)
      ->Array.join(", ")
    let answer: Handler.t = async ctx =>
      switch ctx.method {
      | OPTIONS => Respond.empty(~headers=dict{"allow": allowed})
      | _ => Respond.text(~status=405, ~headers=dict{"allow": allowed}, "Method Not Allowed")
      }
    // Inside the middleware of the first route for this path, so that a
    // scope's middleware sees the request whatever its method: it's how one
    // that answers CORS preflights gets them.
    entry.middleware(answer)(matched)
  })
}
