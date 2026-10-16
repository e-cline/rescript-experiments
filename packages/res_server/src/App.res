type t = Request.t => promise<Response.t>

type onError = (exn, Request.t) => Response.t

let defaultOnError: onError = (error, _request) => {
  Console.error(error)
  Respond.text(~status=500, "Internal Server Error")
}

// `onError`'s response for `error`; if it throws in turn, the default's, so
// that a mistake in an error handler still gets the client an answer.
let answerError = (onError: onError, error: exn, request: Request.t): Response.t =>
  try onError(error, request) catch {
  | failure =>
    Console.error(failure)
    Respond.text(~status=500, "Internal Server Error")
  }

// Answers 400 to a request whose path has a segment no handler should be
// given (see `RequestContext.isSegmentSafe`).
let rejectUnsafePath: Middleware.t = next =>
  async ctx =>
    if ctx->RequestContext.isPathSafe {
      await next(ctx)
    } else {
      Respond.text(~status=400, "Bad Request")
    }

// Turns a failure of the handler it wraps into `onError`'s response.
let recoverWith = (onError: onError): Middleware.t =>
  next =>
    async ctx =>
      try await next(ctx) catch {
      | error => answerError(onError, error, ctx.request)
      }

// The fetch handler for `handler`, with `onError` as the last resort for
// anything that escapes it.
let toFetchHandler = (handler: Handler.t, onError: onError): t =>
  async request => {
    let response = try await handler(RequestContext.make(request)) catch {
    | error => answerError(onError, error, request)
    }
    // Whatever answered it, a HEAD request gets no body.
    request.method == "HEAD" ? response->Respond.withoutBody : response
  }

let make = (handler: Handler.t, ~onError: onError=defaultOnError): t =>
  toFetchHandler(rejectUnsafePath(handler), onError)

type builder<'result> = {
  onError: onError,
  // Every middleware used so far as one, the first outermost.
  middleware: Middleware.t,
  finish: t => 'result,
}

let build = (~onError: onError=defaultOnError): builder<t> => {
  onError,
  middleware: Middleware.none,
  finish: app => app,
}

let use = (builder: builder<'result>, middleware: Middleware.t): builder<'result> => {
  ...builder,
  middleware: handler => builder.middleware(middleware(handler)),
}

let handle = (builder: builder<'result>, handler: Handler.t): 'result => {
  // Innermost, so that what they answer with goes back out through the
  // middleware like any other response.
  let guarded = rejectUnsafePath(recoverWith(builder.onError)(handler))
  builder.finish(toFetchHandler(builder.middleware(guarded), builder.onError))
}

let router = (builder: builder<'result>, routes: array<Route.t>): 'result =>
  builder->handle(Router.make(routes))

let map = (builder: builder<'a>, f: 'a => 'b): builder<'b> => {
  onError: builder.onError,
  middleware: builder.middleware,
  finish: app => f(builder.finish(app)),
}
