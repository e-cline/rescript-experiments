/***
Building Web `Response`s. Every function takes an optional `~status`
(default 200) and extra `~headers`, and sets the `content-type` for you.
*/

let init = (
  ~status: int,
  ~headers: dict<string>=dict{},
  ~contentType: option<string>=?,
): Response.responseInit => {
  let all = Dict.make()
  contentType->Option.forEach(contentType => all->Dict.set("content-type", contentType))
  headers->Dict.forEachWithKey((value, name) => all->Dict.set(name->String.toLowerCase, value))
  {status, headers: HeadersInit.fromDict(all)}
}

let text = (~status: int=200, ~headers: option<dict<string>>=?, body: string): Response.t =>
  Response.fromString(
    body,
    ~init=init(~status, ~headers?, ~contentType="text/plain; charset=utf-8"),
  )

let html = (~status: int=200, ~headers: option<dict<string>>=?, body: Html.t): Response.t =>
  Response.fromString(
    body->Html.toString,
    ~init=init(~status, ~headers?, ~contentType="text/html; charset=utf-8"),
  )

let json = (~status: int=200, ~headers: option<dict<string>>=?, data: JSON.t): Response.t =>
  Response.fromString(
    JSON.stringify(data),
    ~init=init(~status, ~headers?, ~contentType="application/json"),
  )

/**
The same response without its body: what a `HEAD` request is answered with.
A body that is a stream is cancelled, so whatever was producing it stops.
*/
let withoutBody = (response: Response.t): Response.t =>
  switch response.body->Null.toOption {
  | None => response
  | Some(body) =>
    body->ReadableStream.cancel->Promise.catch(_ => Promise.resolve())->ignore
    Response.fromNull(
      ~init={
        status: response.status,
        statusText: response.statusText,
        headers: HeadersInit.fromHeaders(response.headers),
      },
    )
  }

/** A response with no body (204 No Content by default). */
let empty = (~status: int=204, ~headers: option<dict<string>>=?): Response.t =>
  Response.fromNull(~init=init(~status, ~headers?))

/** A redirect to `location` (302 Found by default), which may be relative. */
let redirect = (~status: int=302, ~headers: dict<string>=dict{}, location: string): Response.t => {
  let headers = headers->Dict.copy
  headers->Dict.set("location", location)
  empty(~status, ~headers)
}

let notFound = (~headers: option<dict<string>>=?, ~message: string="Not Found"): Response.t =>
  text(~status=404, ~headers?, message)

/** A response whose body is sent as the stream produces it. */
let stream = (
  ~status: int=200,
  ~headers: option<dict<string>>=?,
  ~contentType: string,
  body: ByteStream.t,
): Response.t => Response.fromReadableStream(body, ~init=init(~status, ~headers?, ~contentType))

let encoder: ByteStream.Encoder.t = ByteStream.Encoder.make()

/**
A streamed text response, one chunk per string `next` returns, until it
returns `None`. `next` is called only when the client is ready for more, and
not again after the client disconnects.

`onEnd` is called once, when the response is over, however that happens: all
of it was sent, the client disconnected, or `next` failed. It's where to
release whatever `next` was reading from.
*/
let textStream = (
  ~status: option<int>=?,
  ~headers: option<dict<string>>=?,
  ~contentType: string="text/plain; charset=utf-8",
  ~onEnd: option<ByteStream.ending => unit>=?,
  next: unit => promise<option<string>>,
): Response.t =>
  stream(
    ~status?,
    ~headers?,
    ~contentType,
    ByteStream.fromPull(~onEnd?, async () =>
      (await next())->Option.map(chunk => encoder->ByteStream.Encoder.encode(chunk))
    ),
  )

/**
A streamed [NDJSON](https://github.com/ndjson/ndjson-spec) (JSON Lines)
response: each value `next` returns is sent as one line of JSON, as soon as
it's available, until `next` returns `None`.
*/
let ndjson = (
  ~status: option<int>=?,
  ~headers: option<dict<string>>=?,
  ~onEnd: option<ByteStream.ending => unit>=?,
  next: unit => promise<option<JSON.t>>,
): Response.t =>
  textStream(
    ~status?,
    ~headers?,
    ~contentType="application/x-ndjson; charset=utf-8",
    ~onEnd?,
    async () => (await next())->Option.map(value => JSON.stringify(value) ++ "\n"),
  )

// Whether a response's headers can be changed. There's no property that says,
// so this asks to remove a header that isn't there: nothing happens if they
// can be, and it throws if they can't.
let hasMutableHeaders = (response: Response.t): bool =>
  switch response.headers->Headers.delete("x-res-server-mutability-probe") {
  | () => true
  | exception _ => false
  }

/**
Changes a response's headers with `change`, returning the response. A
response whose headers are read-only -- one that came from `fetch`, or from
`Response.redirect` -- is copied first, so this works on any response.
`change` is called once, and anything it throws is thrown from here.
*/
let withHeaders = (response: Response.t, change: HttpHeaders.t => unit): Response.t => {
  let response = if response->hasMutableHeaders {
    response
  } else {
    let init: Response.responseInit = {
      status: response.status,
      statusText: response.statusText,
      headers: HeadersInit.fromHeaders(response.headers),
    }
    switch response.body->Null.toOption {
    | Some(body) => Response.fromReadableStream(body, ~init)
    | None => Response.fromNull(~init)
    }
  }
  change(response.headers)
  response
}

/** Sets a header on a response, replacing any value it had. */
let withHeader = (response: Response.t, name: string, value: string): Response.t =>
  response->withHeaders(headers => headers->Headers.set(~name, ~value))

/**
Sets a cookie on a response (see `Cookie.options` for the attributes and
their defaults). Each call adds a `Set-Cookie` header; it doesn't replace
ones already there.
*/
let setCookie = (
  response: Response.t,
  ~options: option<Cookie.options>=?,
  name: string,
  value: string,
): Response.t => {
  let cookie = Cookie.serialize(~options?, name, value)
  response->withHeaders(headers => headers->Headers.append(~name="set-cookie", ~value=cookie))
}

/**
Tells the browser to forget a cookie. `path` and `domain` must be the ones it
was set with, and `partitioned` given if it was (see `Cookie.expire`).
*/
let deleteCookie = (
  response: Response.t,
  ~path: option<string>=?,
  ~domain: option<string>=?,
  ~secure: option<bool>=?,
  ~partitioned: option<bool>=?,
  name: string,
): Response.t => {
  let cookie = Cookie.expire(~path?, ~domain?, ~secure?, ~partitioned?, name)
  response->withHeaders(headers => headers->Headers.append(~name="set-cookie", ~value=cookie))
}
