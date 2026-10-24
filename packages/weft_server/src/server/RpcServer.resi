/***
Answering Weft RPCs, on the server (declaring and calling them is `Rpc`'s, in shared code): each
RPC's handler, and a router that answers the RPCs it's given, and no others.

```rescript
// src/ApiServer.res
@@weft.server

let addComment = WeftServer.RpcServer.handler(Api.addComment, async (request, ~http as _) =>
  Ok(Db.addComment(request))
)
let router = WeftServer.RpcServer.router([addComment])

// src/Server.res
Route.post(list{"_weft", "rpc", ":id"}, async ctx =>
  await ApiServer.router->WeftServer.RpcServer.respond(
    ctx.request,
    ~id=ctx->RequestContext.paramOrThrow("id"),
  )
)
```

Server only: an app's client build refuses this module (see the Vite plugin), as it does the app's
own `@@weft.server` files.
*/

/** An RPC's handler, for `router`. */
type handler

/**
What the server does for `rpc`: given a request the codec read and `check` accepted, and the HTTP
request it came in (for its headers, cookies and `signal`), the response, or the RPC's own error.
*/
let handler: (
  Rpc.t<'input, 'request, 'response, 'error>,
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
6. otherwise the handler's result is the answer, as a payload, with `Payload.cacheControl`. A
   handler that throws is a 500 (`Failed`), with the digest `onError` gave it and, in development
   only, its message.
*/
let respond: (router, Request.t, ~id: string) => promise<Response.t>

/** The IDs the router answers, sorted. */
let ids: router => array<string>
