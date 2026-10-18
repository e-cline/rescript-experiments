/***
Helpers shared by this package's tests.
*/

/** A `Request` for `path` on a made-up host. */
let request = (
  ~method: string="GET",
  ~headers: dict<string>=dict{},
  ~body: option<string>=?,
  path: string,
): Request.t =>
  Request.fromURL(
    `http://example.test${path}`,
    ~init={
      method,
      headers: HeadersInit.fromDict(headers),
      body: ?(body->Option.map(BodyInit.fromString)),
    },
  )

/** A context for `path`, as `App` would make it. */
let context = (
  ~method: option<string>=?,
  ~headers: option<dict<string>>=?,
  ~body: option<string>=?,
  path: string,
): RequestContext.t => RequestContext.make(request(~method?, ~headers?, ~body?, path))

let contentType = (response: Response.t): option<string> =>
  response.headers->HttpHeaders.get("content-type")

/** Reads a streamed body to its end, as the text of each chunk. */
let chunks = async (response: Response.t): array<string> =>
  switch response.body->Null.toOption {
  | Some(body) => await body->ByteStream.fromBody->ByteStream.toTextChunks
  | None => []
  }

type console

@val external console: console = "console"
@get external consoleError: console => 'error = "error"
@set external setConsoleError: (console, 'error) => unit = "error"

/**
Runs `f` with `console.error` replaced by something that only counts its
calls, for tests of things that log an error on purpose. Returns `f`'s result
and the count.
*/
let countingConsoleErrors = async (f: unit => promise<'result>): ('result, int) => {
  let original = console->consoleError
  let calls = ref(0)
  console->setConsoleError(() => calls := calls.contents + 1)
  let result = try Ok(await f()) catch {
  | error => Error(error)
  }
  console->setConsoleError(original)
  switch result {
  | Ok(value) => (value, calls.contents)
  | Error(error) => throw(error)
  }
}

let sleep = (ms: int): promise<unit> =>
  Promise.make((resolve, _) => setTimeout(() => resolve(), ms)->ignore)
