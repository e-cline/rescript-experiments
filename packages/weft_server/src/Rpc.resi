/***
Weft RPCs: functions that run on the server, which the client calls as if they were local. Each has
an ID its author chose, typed input, response and error, and an optional step on the client before
anything is sent. A call is

```rescript
'input => promise<result<'response, WeftServer.Rpc.error<'error>>>
```

and its promise doesn't reject: every way a call can fail is an `Error`.

An RPC is declared in shared code (the client imports it), and handled in a server-only file:

```rescript
// src/Api.res: shared
@weft.rpc({id: "notes.addComment"})
let addComment: WeftServer.Rpc.t<addComment, addComment, Types.comment, Errors.comment> =
  WeftServer.Rpc.make(~request=addCommentCodec, ~check=request =>
    String.length(request.text) > 2000 ? Error(Errors.TooLong) : Ok()
  )

// src/ApiServer.res: server only
@@weft.server

let addComment = WeftServer.Rpc.handler(Api.addComment, async (request, ~http as _) =>
  Ok(Db.addComment(request))
)

// src/Server.res: the RPCs the server answers, by listing their handlers
let rpcs = WeftServer.Rpc.router([ApiServer.addComment])
Route.post(list{"_weft", "rpc", ":id"}, async ctx =>
  await rpcs->WeftServer.Rpc.respond(ctx.request, ~id=ctx->RequestContext.paramOrThrow("id"))
)

// in an entrypoint
let addComment = WeftServer.Rpc.use(Api.addComment)
switch await addComment(values) {
| Ok(comment) => ...
| Error(Rejected(error)) => ... // from `prepare` or `check` (nothing was sent), or the handler
| Error(Invalid(_)) => ...      // the server couldn't read the request
| Error(Failed(problem)) => ... // the network, an unknown RPC, a handler that threw
}
```

**Requests are plain JSON**, written and read by the RPC's codec (`Codec`), never by the payload
decoder: a request is anyone's, and a decoder that follows references and loads modules is for the
server's own output. **Responses are payloads** (`Render`'s), so a response can be or contain
elements (server components' output) and promises, which stream in after it.

Every RPC the router lists is a public endpoint: anyone can call it, with any body. Authentication
and authorization are the handler's (from `~http`), or a middleware's around the route.
*/

/** A `ReadableStream`'s `AbortSignal`. */
type signal = Streams.Signal.t

/** How a request goes over the wire. See `RpcCodec`. */
module Codec = RpcCodec

/** What went wrong with a call that didn't get as far as the RPC's own answer. */
type problem = {
  /** The response's status, if there was one. */
  status: option<int>,
  /** What went wrong (in a production build, only a generic message). */
  message: string,
  /** The digest the server's `onError` gave a handler's error, if any. */
  digest: option<string>,
}

type error<'error> =
  /** `prepare` or `check` said no (on the client: nothing was sent), or the handler returned `Error`. */
  | Rejected('error)
  /** The server couldn't read the request (a client older or newer than it, or a forged request). */
  | Invalid(string)
  /** Anything else: the network, an unknown RPC, a handler that threw. */
  | Failed(problem)

/**
An RPC: what the caller passes (`'input`), what goes over the wire (`'request`), what comes back
(`'response`), and the RPC's own errors (`'error`).
*/
type t<'input, 'request, 'response, 'error>

/**
Whether `id` is an RPC ID: names separated by dots (`notes.addComment`, `Billing.refund`), each a
letter then letters, digits and `_`.
*/
let isValidId: string => bool

/**
An RPC named `id` (which `@weft.rpc({id: "..."})` passes, after checking it), whose request is
written and read with `request`. `check`, if given, runs on both sides: on the client before
sending, for quick feedback, and again on the server, which can't trust the client to have.
`maxBytes` is the most a request's body can be (by default, the router's). Fails if `id` isn't
valid.
*/
let make: (
  ~id: string,
  ~request: Codec.t<'request>,
  ~check: 'request => result<unit, 'error>=?,
  ~maxBytes: int=?,
) => t<'request, 'request, 'response, 'error>

/**
`make`, with a step on the client first: `prepare` turns the caller's input into the request
(trimming it, say, or reading something only the client has), or says no, and nothing is sent.
*/
let makePrepared: (
  ~id: string,
  ~request: Codec.t<'request>,
  ~prepare: 'input => promise<result<'request, 'error>>,
  ~check: 'request => result<unit, 'error>=?,
  ~maxBytes: int=?,
) => t<'input, 'request, 'response, 'error>

/** The RPC's ID. */
let id: t<_, _, _, _> => string

// The client

/** Where the router is mounted, by default: an RPC is `POST`ed to `<base>/<id>`. */
let defaultBase: string

/**
Calls `rpc` with `input`: runs `prepare` and `check`, then `POST`s the request to `<base>/<id>`, and
decodes the response with `client`. Aborting `signal` cancels the request (and the handler's
`http.signal` on the server), and the call is then `Failed`.
*/
let call: (
  t<'input, 'request, 'response, 'error>,
  ~client: Client.t,
  'input,
  ~base: string=?,
  ~signal: signal=?,
) => promise<result<'response, error<'error>>>

/** `call`, as a function bound to the client of the page the entrypoint is on. Fails outside one. */
let use: (
  t<'input, 'request, 'response, 'error>,
  ~base: string=?,
) => 'input => promise<result<'response, error<'error>>>

// The server

/** An RPC's handler, for `router`. */
type handler

/**
What the server does for `rpc`: given a request the codec read and `check` accepted, and the HTTP
request it came in (for its headers, cookies and `signal`), the response, or the RPC's own error.
*/
let handler: (
  t<'input, 'request, 'response, 'error>,
  ('request, ~http: Request.t) => promise<result<'response, 'error>>,
) => handler

type router

/**
Answers the RPCs `handlers` are for, and no others. Fails if two have the same ID.

- `maxBytes`: the most a request's body can be, for an RPC that doesn't say (64 KB by default).
- `origins`: the origins a request can come from (by default, only the server's own, from the
  request's URL). Requests a browser sends say where they come from (`Origin`).
- `onError`: called with each error a handler throws (by default, logging with `Console.error`),
  returning the digest to send with it, if any (as `Render.toStream`'s does).
*/
let router: (
  array<handler>,
  ~maxBytes: int=?,
  ~origins: array<string>=?,
  ~onError: exn => option<string>=?,
) => router

/**
The response to `request`, a call of the RPC `id`. In order:

1. an `id` the router doesn't have is a 404;
2. anything but a `POST` is a 405; a `content-type` other than `application/json` is a 415; no
   `x-weft-rpc: 1` header, or an `Origin` that isn't allowed, is a 403 (a form on another site can't
   send JSON or set a header without the browser asking first, which is the CSRF protection);
3. a body over the size limit is a 413;
4. a body that isn't JSON, or that the codec can't read, is `Invalid` (a 400), and nothing else
   runs;
5. `check` saying no is `Rejected`, and the handler isn't called;
6. otherwise the handler's result is the answer, as a payload, with `cache-control: no-store`. A
   handler that throws is a 500 (`Failed`), with the digest `onError` gave it and, in development
   only, its message.
*/
let respond: (router, Request.t, ~id: string) => promise<Response.t>

/** The IDs the router answers, sorted. */
let ids: router => array<string>
