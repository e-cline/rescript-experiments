type signal = Streams.Signal.t

module Codec = RpcCodec

type problem = {status: option<int>, message: string, digest: option<string>}

type error<'error> =
  | Rejected('error)
  | Invalid(string)
  | Failed(problem)

type t<'input, 'request, 'response, 'error> = {
  id: string,
  request: Codec.t<'request>,
  prepare: option<'input => promise<result<'request, 'error>>>,
  check: option<'request => result<unit, 'error>>,
  maxBytes: option<int>,
}

let idPattern = /^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)*$/

let isValidId = id => idPattern->RegExp.test(id)

let checkId = id =>
  if !isValidId(id) {
    Errors.fail(
      18,
      Common.Env.isDev
        ? `WeftServer: "${id}" isn't an RPC ID: it's names separated by dots, each a letter then letters, digits and _ (notes.addComment, say)`
        : "",
    )
  }

let makePrepared = (~id, ~request, ~prepare, ~check=?, ~maxBytes=?) => {
  checkId(id)
  {id, request, prepare: Some(prepare), check, maxBytes}
}

let make = (~id, ~request, ~check=?, ~maxBytes=?) => {
  checkId(id)
  {id, request, prepare: None, check, maxBytes}
}

let id = rpc => rpc.id

// The wire

/** The root of a response's payload: what the handler answered, or why there's no answer. */
let kindOk = "ok"
let kindError = "error"
let kindInvalid = "invalid"

let rpcHeader = "x-weft-rpc"

let defaultBase = "/_weft/rpc"

let defaultMaxBytes = 65536

external toUnknown: 'a => unknown = "%identity"
external fromUnknown: unknown => 'a = "%identity"

// The client

type headers
@send external getHeader: (headers, string) => Nullable.t<string> = "get"

type fetchResponse = {ok: bool, status: int, headers: headers, body: Nullable.t<Streams.t>}
type fetchInit = {
  method: string,
  headers: dict<string>,
  body: string,
  signal?: signal,
}
@val external fetch: (string, fetchInit) => promise<fetchResponse> = "fetch"

@get_index external field: (unknown, string) => unknown = ""
let hasOwn: (unknown, string) => bool = %raw(`(object, name) =>
  object !== null && typeof object === "object" && Object.hasOwn(object, name)`)
@get external digestOf: JsExn.t => Nullable.t<string> = "digest"

let failed = (~status=?, ~digest=?, message) => Error(
  Failed({
    status,
    message: Common.Env.isDev ? `WeftServer: ${message}` : "WeftServer: an RPC failed",
    digest,
  }),
)

/** What a call's thrown error was, as a `Failed`. */
let failedWith = (~status=?, prefix, error: exn) =>
  switch error {
  | JsExn(error) =>
    failed(
      ~status?,
      ~digest=?digestOf(error)->Nullable.toOption,
      `${prefix}: ${JsExn.message(error)->Option.getOr("an error")}`,
    )
  | error => failed(~status?, `${prefix}: ${Values.describeError(error)}`)
  }

let isPayload = (response: fetchResponse) =>
  switch response.headers->getHeader("content-type")->Nullable.toOption {
  | Some(contentType) => contentType->String.startsWith(Payload.contentType)
  | None => false
  }

/** Sends `request` and reads the answer. */
let send = async (rpc, ~client, request, ~base, ~signal) => {
  let url = `${base}/${rpc.id}`
  switch await fetch(
    url,
    {
      method: "POST",
      headers: dict{
        "content-type": "application/json",
        "x-weft-rpc": "1",
        "accept": Payload.contentType,
      },
      body: JSON.stringify(Codec.encode(rpc.request, request)),
      ?signal,
    },
  ) {
  | exception error => failedWith(`calling the RPC ${rpc.id} failed`, error)
  | response =>
    switch (isPayload(response), Nullable.toOption(response.body)) {
    | (true, Some(body)) =>
      switch await Client.valueFromStream(client, body, ~signal?) {
      | root =>
        let kind = hasOwn(root, "kind") ? field(root, "kind") : toUnknown(Nullable.null)
        if kind === toUnknown(kindOk) {
          Ok(fromUnknown(field(root, "value")))
        } else if kind === toUnknown(kindError) {
          Error(Rejected(fromUnknown(field(root, "error"))))
        } else if kind === toUnknown(kindInvalid) {
          Error(Invalid(fromUnknown(field(root, "message"))))
        } else {
          failed(~status=response.status, `the RPC ${rpc.id}'s response isn't one`)
        }
      | exception error => failedWith(~status=response.status, `the RPC ${rpc.id} failed`, error)
      }
    | _ =>
      failed(
        ~status=response.status,
        `calling the RPC ${rpc.id} failed with status ${Int.toString(response.status)}`,
      )
    }
  }
}

let call = async (rpc, ~client, input, ~base=defaultBase, ~signal=?) => {
  let prepared = switch rpc.prepare {
  | Some(prepare) => await prepare(input)
  // Without `prepare`, the input is the request (`make`'s type says so).
  | None => Ok(fromUnknown(toUnknown(input)))
  }
  switch prepared {
  | Error(error) => Error(Rejected(error))
  | Ok(request) =>
    switch rpc.check->Option.mapOr(Ok(), check => check(request)) {
    | Error(error) => Error(Rejected(error))
    | Ok() => await send(rpc, ~client, request, ~base, ~signal)
    }
  }
}

/** `call`, with what `prepare` or `check` throw as a `Failed` rather than a rejection. */
let call = async (rpc, ~client, input, ~base=?, ~signal=?) =>
  switch await call(rpc, ~client, input, ~base?, ~signal?) {
  | result => result
  | exception error => failedWith(`the RPC ${rpc.id} failed on the client`, error)
  }

let use = (rpc, ~base=?) => {
  let navigation = Navigation.useNavigation()
  WeftCore.Hooks.useCallback2(
    input => call(rpc, ~client=Navigation.client(navigation), input, ~base?),
    (navigation, rpc),
  )
}

// The server

/** A handler, its types hidden: it reads the request itself. */
type handler = {
  handlerId: string,
  maxBytes: option<int>,
  /** Reads the request, checks it, and calls the handler: the root of the response. */
  run: (JSON.t, Request.t) => promise<(int, dict<unknown>)>,
}

let handler = (rpc, handle) => {
  handlerId: rpc.id,
  maxBytes: rpc.maxBytes,
  run: async (json, http) =>
    switch Codec.decode(rpc.request, json) {
    | Error(message) => (400, dict{"kind": toUnknown(kindInvalid), "message": toUnknown(message)})
    | Ok(request) =>
      switch rpc.check->Option.mapOr(Ok(), check => check(request)) {
      | Error(error) => (200, dict{"kind": toUnknown(kindError), "error": toUnknown(error)})
      | Ok() =>
        switch await handle(request, ~http) {
        | Ok(value) => (200, dict{"kind": toUnknown(kindOk), "value": toUnknown(value)})
        | Error(error) => (200, dict{"kind": toUnknown(kindError), "error": toUnknown(error)})
        }
      }
    },
}

type router = {
  handlers: Map.t<string, handler>,
  maxBytes: int,
  origins: option<array<string>>,
  onError: exn => option<string>,
}

let defaultOnError = error => {
  Console.error(error)
  None
}

let router = (handlers, ~maxBytes=defaultMaxBytes, ~origins=?, ~onError=defaultOnError) => {
  let byId = Map.make()
  handlers->Array.forEach(handler => {
    if byId->Map.has(handler.handlerId) {
      Errors.fail(
        19,
        Common.Env.isDev
          ? `WeftServer: the router has two handlers for the RPC ${handler.handlerId}`
          : "",
      )
    }
    byId->Map.set(handler.handlerId, handler)
  })
  {handlers: byId, maxBytes, origins, onError}
}

let ids = router => router.handlers->Map.keys->Array.fromIterator->Array.toSorted(String.compare)

external toBody: Streams.t => ReadableStream.t<Uint8Array.t> = "%identity"
external toSignal: EventTypes.abortSignal => Streams.Signal.t = "%identity"
@get external bodyOf: Request.t => Nullable.t<Streams.t> = "body"

/** A refusal, before anything of the RPC's ran: plain text. */
let refuse = (status, message) =>
  Response.fromString(
    message,
    ~init={
      status,
      headers: HeadersInit.fromDict(
        dict{"content-type": "text/plain; charset=utf-8", "cache-control": "no-store"},
      ),
    },
  )

let payloadResponse = (status, body) =>
  Response.fromReadableStream(
    toBody(body),
    ~init={
      status,
      headers: HeadersInit.fromDict(
        dict{"content-type": Payload.contentType, "cache-control": "no-store"},
      ),
    },
  )

/** A payload whose root is the error a handler threw (so the client's decoding of it fails). */
let failure = (router, error) => {
  let digest = try router.onError(error) catch {
  | _ => None
  }
  let fields = dict{}
  digest->Option.forEach(digest => fields->Dict.set("digest", JSON.Encode.string(digest)))
  if Common.Env.isDev {
    fields->Dict.set("message", JSON.Encode.string(Values.describeError(error)))
  }
  let row = Payload.rowToString({id: 0, tag: Error, json: JSON.Encode.object(fields)})
  Streams.make({
    start: controller => {
      controller->Streams.enqueue(Streams.Encoder.make()->Streams.Encoder.encode(row))
      controller->Streams.close
    },
  })
}

let invalid = message =>
  payloadResponse(
    400,
    Render.valueToStream(
      toUnknown(dict{"kind": toUnknown(kindInvalid), "message": toUnknown(message)}),
    ),
  )

let header = (request: Request.t, name) => request.headers->Headers.get(name)->Null.toOption

let isJson = contentType =>
  switch contentType {
  | Some(contentType) =>
    switch contentType->String.split(";")->Array.get(0) {
    | Some(mediaType) => mediaType->String.trim->String.toLowerCase == "application/json"
    | None => false
    }
  | None => false
  }

type url = {origin: string}
@new external parseUrl: string => url = "URL"

/** Whether the request came from somewhere allowed, as far as the browser that sent it says. */
let isAllowedOrigin = (router, request: Request.t) =>
  switch header(request, "origin") {
  | Some(origin) =>
    switch router.origins {
    | Some(origins) => origins->Array.includes(origin)
    | None =>
      switch parseUrl(request.url) {
      | url => url.origin == origin
      | exception _ => false
      }
    }
  // Not from a browser (one sends `Origin` with every `POST`), or one that says the request is
  // another site's.
  | None => header(request, "sec-fetch-site") != Some("cross-site")
  }

module Decoder = {
  type t
  type options = {fatal: bool}
  type decodeOptions = {stream: bool}
  @new external make: (string, options) => t = "TextDecoder"
  @send external decode: (t, Uint8Array.t, decodeOptions) => string = "decode"
  @send external finish: t => string = "decode"
}

/** The body, as text, if it's no more than `limit` bytes (`None` if it's more). Throws if it isn't UTF-8. */
let readBody = async (request, ~limit) =>
  switch bodyOf(request)->Nullable.toOption {
  | None => Some("")
  | Some(body) =>
    let reader = body->Streams.getReader
    let decoder = Decoder.make("utf-8", {fatal: true})
    let text = []
    let size = ref(0)
    let tooBig = ref(false)
    let finished = ref(false)
    while !finished.contents {
      switch await reader->Streams.Reader.read {
      | {done: false, value} =>
        size := size.contents + TypedArray.length(value)
        if size.contents > limit {
          tooBig := true
          finished := true
          reader->Streams.Reader.cancel->Promise.catch(_ => Promise.resolve())->ignore
        } else {
          text->Array.push(decoder->Decoder.decode(value, {stream: true}))
        }
      | _ => finished := true
      }
    }
    if tooBig.contents {
      None
    } else {
      text->Array.push(decoder->Decoder.finish)
      Some(text->Array.join(""))
    }
  }

let respond = async (router, request: Request.t, ~id) =>
  switch router.handlers->Map.get(id) {
  | None => refuse(404, `There's no RPC ${id}.`)
  | Some(handler) =>
    let limit = handler.maxBytes->Option.getOr(router.maxBytes)
    let declaredSize =
      header(request, "content-length")->Option.flatMap(length => Int.fromString(length))
    if request.method != "POST" {
      refuse(405, "An RPC is called with POST.")
    } else if !isJson(header(request, "content-type")) {
      refuse(415, "An RPC's request is JSON (content-type: application/json).")
    } else if header(request, rpcHeader) != Some("1") {
      refuse(403, `An RPC's request has the header ${rpcHeader}: 1.`)
    } else if !isAllowedOrigin(router, request) {
      refuse(403, "This RPC can't be called from another site.")
    } else if declaredSize->Option.mapOr(false, size => size > limit) {
      refuse(413, "The request is too big.")
    } else {
      switch await readBody(request, ~limit) {
      | exception _ => invalid("the request's body couldn't be read (or isn't UTF-8)")
      | None => refuse(413, "The request is too big.")
      | Some(text) =>
        switch JSON.parseOrThrow(text) {
        | exception _ => invalid("the request isn't JSON")
        | json =>
          switch await handler.run(json, request) {
          | (status, root) =>
            payloadResponse(
              status,
              Render.valueToStream(
                toUnknown(root),
                ~onError=router.onError,
                ~signal=toSignal(request.signal),
              ),
            )
          | exception error => payloadResponse(500, failure(router, error))
          }
        }
      }
    }
  }
