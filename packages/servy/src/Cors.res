type origins =
  | Any
  | Only(array<string>)
  | Where(string => bool)

let defaultMethods: array<Method.t> = [GET, HEAD, POST, PUT, PATCH, DELETE]

let middleware = (
  ~origins: origins,
  ~methods: array<Method.t>=defaultMethods,
  ~allowHeaders: option<array<string>>=?,
  ~exposeHeaders: array<string>=[],
  ~credentials: bool=false,
  ~maxAge: option<int>=?,
): Middleware.t => {
  let anyOrigin = switch origins {
  | Any => true
  | Only(_) | Where(_) => false
  }
  if credentials && anyOrigin {
    JsError.throwWithMessage(
      "Cors.middleware: `~credentials=true` can't be combined with `~origins=Any`. List the allowed origins instead.",
    )
  }
  let isAllowed = (origin: string): bool =>
    switch origins {
    | Any => true
    | Only(allowed) => allowed->Array.includes(origin)
    | Where(allows) => allows(origin)
    }
  if credentials {
    // With credentials, an allowed origin can act as a visitor who is logged
    // in here. These are origins that no deliberate list has on it: a
    // predicate that lets them through lets everything through.
    ["null", "https://servy-probe.invalid"]->Array.forEach(origin =>
      if isAllowed(origin) {
        JsError.throwWithMessage(
          `Cors.middleware: with \`~credentials=true\`, \`~origins\` allows the origin "${origin}". "null" is what sandboxed pages and local files send, and the other belongs to nobody, so allowing either means any site can act as a visitor who is logged in here. Allow only the origins you mean to.`,
        )
      }
    )
  }
  let methods = methods->Array.map(Method.toString)->Array.join(", ")

  // The headers every answer to a request from an allowed `origin` gets.
  let allowOrigin = (headers: HttpHeaders.t, origin: string): unit => {
    headers->Headers.set(~name="access-control-allow-origin", ~value=anyOrigin ? "*" : origin)
    if credentials {
      headers->Headers.set(~name="access-control-allow-credentials", ~value="true")
    }
  }
  // The answer depends on the request's `Origin`, unless it's always `*`;
  // without this a cache could hand one origin's answer to another.
  let varyOnOrigin = (headers: HttpHeaders.t): unit =>
    if !anyOrigin {
      headers->Headers.append(~name="vary", ~value="Origin")
    }

  let preflight = (ctx: RequestContext.t, origin: string): Response.t =>
    Respond.empty()->Respond.withHeaders(headers => {
      headers->varyOnOrigin
      if isAllowed(origin) {
        headers->allowOrigin(origin)
        headers->Headers.set(~name="access-control-allow-methods", ~value=methods)
        switch allowHeaders {
        | Some(allowHeaders) =>
          headers->Headers.set(
            ~name="access-control-allow-headers",
            ~value=allowHeaders->Array.join(", "),
          )
        | None =>
          // Allow what's asked for.
          ctx
          ->RequestContext.header("access-control-request-headers")
          ->Option.forEach(requested => {
            headers->Headers.set(~name="access-control-allow-headers", ~value=requested)
            headers->Headers.append(~name="vary", ~value="Access-Control-Request-Headers")
          })
        }
        maxAge->Option.forEach(maxAge =>
          headers->Headers.set(~name="access-control-max-age", ~value=maxAge->Int.toString)
        )
      }
    })

  next =>
    async ctx =>
      switch (ctx.method, ctx->RequestContext.header("origin")) {
      | (OPTIONS, Some(origin))
        if ctx->RequestContext.header("access-control-request-method")->Option.isSome =>
        preflight(ctx, origin)
      | (_, origin) =>
        (await next(ctx))->Respond.withHeaders(headers => {
          headers->varyOnOrigin
          // With `Any` the answer is the same for everyone, so it's marked
          // whether or not this request named an origin: a cache may hand it
          // to one that does.
          let allowed = anyOrigin ? Some("*") : origin->Option.filter(isAllowed)
          allowed->Option.forEach(origin => {
            headers->allowOrigin(origin)
            if exposeHeaders->Array.length > 0 {
              headers->Headers.set(
                ~name="access-control-expose-headers",
                ~value=exposeHeaders->Array.join(", "),
              )
            }
          })
        })
      }
}
