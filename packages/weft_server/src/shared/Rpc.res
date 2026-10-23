type signal = Streams.Signal.t

module Codec = RpcCodec

type problem = {status: option<int>, message: string, digest: option<string>}

type error<'error> =
  | Rejected('error)
  | Invalid(string)
  | Failed(problem)

type t<'input, 'request, 'response, 'error> = RpcCore.t<'input, 'request, 'response, 'error> = {
  id: string,
  request: RpcCodec.t<'request>,
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

let defaultBase = RpcCore.defaultBase

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
      switch await Decoder.valueFromStream(client, body, ~signal?) {
      | root =>
        let kind = hasOwn(root, "kind") ? field(root, "kind") : toUnknown(Nullable.null)
        if kind === toUnknown(RpcCore.kindOk) {
          Ok(fromUnknown(field(root, "value")))
        } else if kind === toUnknown(RpcCore.kindError) {
          Error(Rejected(fromUnknown(field(root, "error"))))
        } else if kind === toUnknown(RpcCore.kindInvalid) {
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
  Weft.Hooks.useCallback2(
    input => call(rpc, ~client=Navigation.client(navigation), input, ~base?),
    (navigation, rpc),
  )
}
