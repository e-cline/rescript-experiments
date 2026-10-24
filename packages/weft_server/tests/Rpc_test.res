@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/***
Weft RPCs: the router against hand-made requests (what it refuses, and that nothing of the RPC's
runs for a request it refuses or can't read), a fuzz test of random bodies, and calls from the
client through the router, in process.
*/

open Vitest
open Support

module Codec = Rpc.Codec

type comment = {noteId: string, text: string}

let commentCodec = Codec.object2(
  ("noteId", Codec.string),
  ("text", Codec.string),
  (noteId, text) => {noteId, text},
  ({noteId, text}) => (noteId, text),
)

type commentError = TooLong | NoSuchNote | Empty

let addComment: Rpc.t<comment, comment, string, commentError> = Rpc.make(
  ~id="notes.addComment",
  ~request=commentCodec,
  ~check=comment => String.length(comment.text) > 20 ? Error(TooLong) : Ok(),
)

/** What the handlers were called with, in order. */
let calls: array<comment> = []

/** Resolved by a test, for a handler waiting on it. */
let gate = ref(Deferred.make())
/** Whether the last handler that waited saw its request aborted. */
let sawAbort = ref(false)

@get external signalOf: Request.t => EventTypes.abortSignal = "signal"
external toSignal: EventTypes.abortSignal => Streams.Signal.t = "%identity"

let addCommentHandler = RpcServer.handler(addComment, async (comment, ~http) => {
  calls->Array.push(comment)
  switch comment.text {
  | "throw" => JsError.throwWithMessage("the database is down")
  | "wait" =>
    let signal = toSignal(signalOf(http))
    signal->Streams.Signal.onAbort(() => sawAbort := true, {once: true})
    await gate.contents.promise
    Ok("waited")
  | _ if comment.noteId == "missing" => Error(NoSuchNote)
  | text => Ok(`saved ${text}`)
  }
})

type later = {label: string, later: promise<string>}

let later: Rpc.t<string, string, later, unit> = Rpc.make(~id="notes.later", ~request=Codec.string)
let laterHandler = RpcServer.handler(later, async (label, ~http as _) => Ok({
  label,
  later: gate.contents.promise->Promise.thenResolve(_ => `${label}, later`),
}))

let render: Rpc.t<string, string, Weft.Element.t, unit> = Rpc.make(
  ~id="notes.render",
  ~request=Codec.string,
)
let renderHandler = RpcServer.handler(render, async (id, ~http as _) => Ok(
  <Wrap id>
    <Counter label=id />
  </Wrap>,
))

let small: Rpc.t<string, string, unit, unit> = Rpc.make(
  ~id="notes.small",
  ~request=Codec.string,
  ~maxBytes=10,
)
let smallHandler = RpcServer.handler(small, async (_, ~http as _) => Ok())

let digests = []
let router = RpcServer.router(
  [addCommentHandler, laterHandler, renderHandler, smallHandler],
  ~onError=error => {
    digests->Array.push(Values.describeError(error))
    Some("digest-1")
  },
)

let origin = "http://notes.test"

type requestInit = {
  method: string,
  headers: dict<string>,
  body?: string,
  signal?: Streams.Signal.t,
}
@new external makeRequest: (string, requestInit) => Request.t = "Request"

let rpcHeaders = () => dict{"content-type": "application/json", "x-weft-rpc": "1"}

let post = (~id="notes.addComment", ~headers=rpcHeaders(), ~method="POST", body) =>
  router->RpcServer.respond(
    makeRequest(
      `${origin}/_weft/rpc/${id}`,
      method == "GET" ? {method, headers} : {method, headers, body},
    ),
    ~id,
  )

@send external text: Response.t => promise<string> = "text"
@get external status: Response.t => int = "status"
type headers
@get external headersOf: Response.t => headers = "headers"
@send external getHeader: (headers, string) => Nullable.t<string> = "get"
@get external bodyOf: Response.t => Streams.t = "body"

let contentType = response => response->headersOf->getHeader("content-type")->Nullable.toOption

/** A response's payload rows. */
let rowsOf = async response => rows(await text(response))

let resetCalls = () => {
  calls->Array.splice(~start=0, ~remove=Array.length(calls), ~insert=[])
  digests->Array.splice(~start=0, ~remove=Array.length(digests), ~insert=[])
  gate := Deferred.make()
  sawAbort := false
}

describe("the router", () => {
  beforeEach(resetCalls)

  testAsync("answers a call with the handler's response, as a payload", async t => {
    let response = await post(`{"noteId": "1", "text": "hi"}`)
    t->expect(status(response))->Expect.toBe(200)
    t->expect(contentType(response))->Expect.toEqual(Some(Payload.contentType))
    t
    ->expect(response->headersOf->getHeader("cache-control")->Nullable.toOption)
    ->Expect.toEqual(Some(Payload.cacheControl))
    t->expect(await rowsOf(response))->Expect.toEqual([`0:J{"kind":"ok","value":"saved hi"}`])
    t->expect(calls)->Expect.toEqual([{noteId: "1", text: "hi"}])
  })

  testAsync("answers a handler's Error, and check's, with the error", async t => {
    t
    ->expect(await rowsOf(await post(`{"noteId": "missing", "text": "hi"}`)))
    ->Expect.toEqual([`0:J{"kind":"error","error":"NoSuchNote"}`])
    let response = await post(`{"noteId": "1", "text": "this is far too long to be a comment"}`)
    t->expect(status(response))->Expect.toBe(200)
    t->expect(await rowsOf(response))->Expect.toEqual([`0:J{"kind":"error","error":"TooLong"}`])
    // `check` said no: the handler wasn't called.
    t->expect(calls->Array.map(call => call.noteId))->Expect.toEqual(["missing"])
  })

  testAsync("answers a request the codec can't read with Invalid, calling nothing", async t => {
    let response = await post(`{"noteId": 1, "text": "hi"}`)
    t->expect(status(response))->Expect.toBe(400)
    t
    ->expect(await rowsOf(response))
    ->Expect.toEqual([`0:J{"kind":"invalid","message":".noteId: expected a string, got a number"}`])
    t->expect(calls)->Expect.toEqual([])
  })

  testAsync("answers malformed JSON, and very deep nesting, with Invalid", async t => {
    let malformed = await post(`{"noteId": `)
    t->expect(status(malformed))->Expect.toBe(400)
    t
    ->expect(await rowsOf(malformed))
    ->Expect.toEqual([`0:J{"kind":"invalid","message":"the request isn't JSON"}`])
    let deep = String.repeat("[", 30000) ++ String.repeat("]", 30000)
    t->expect(status(await post(deep)))->Expect.toBe(400)
    let deepObject = String.repeat(`{"a":`, 10000) ++ "1" ++ String.repeat("}", 10000)
    t->expect(status(await post(deepObject)))->Expect.toBe(400)
    t->expect(calls)->Expect.toEqual([])
  })

  testAsync("answers an ID it doesn't have, prototype names among them, with a 404", async t => {
    for index in 0 to 5 {
      let id =
        [
          "__proto__",
          "constructor",
          "toString",
          "hasOwnProperty",
          "notes",
          "notes.other",
        ]->Array.getUnsafe(index)
      let response = await post(~id, `{"noteId": "1", "text": "hi"}`)
      t->expect(status(response))->Expect.toBe(404)
    }
    t->expect(calls)->Expect.toEqual([])
  })

  testAsync(
    "refuses the wrong method, content type, header or origin, before reading the body",
    async t => {
      let body = `{"noteId": "1", "text": "hi"}`
      t->expect(status(await post(~method="GET", body)))->Expect.toBe(405)
      t->expect(status(await post(~method="PUT", body)))->Expect.toBe(405)
      let withHeaders = change => {
        let headers = rpcHeaders()
        change(headers)
        headers
      }
      t
      ->expect(
        status(
          await post(~headers=withHeaders(h => h->Dict.set("content-type", "text/plain")), body),
        ),
      )
      ->Expect.toBe(415)
      t
      ->expect(
        status(
          await post(
            ~headers=withHeaders(
              h => h->Dict.set("content-type", "application/x-www-form-urlencoded"),
            ),
            body,
          ),
        ),
      )
      ->Expect.toBe(415)
      t
      ->expect(status(await post(~headers=withHeaders(h => h->Dict.delete("x-weft-rpc")), body)))
      ->Expect.toBe(403)
      t
      ->expect(
        status(await post(~headers=withHeaders(h => h->Dict.set("x-weft-rpc", "yes")), body)),
      )
      ->Expect.toBe(403)
      t
      ->expect(
        status(
          await post(~headers=withHeaders(h => h->Dict.set("origin", "http://evil.test")), body),
        ),
      )
      ->Expect.toBe(403)
      t
      ->expect(
        status(
          await post(~headers=withHeaders(h => h->Dict.set("sec-fetch-site", "cross-site")), body),
        ),
      )
      ->Expect.toBe(403)
      t->expect(calls)->Expect.toEqual([])
      // Its own origin, and a charset, are fine.
      let ok = await post(
        ~headers=withHeaders(
          h => {
            h->Dict.set("origin", origin)
            h->Dict.set("content-type", "application/json; charset=utf-8")
          },
        ),
        body,
      )
      t->expect(status(ok))->Expect.toBe(200)
    },
  )

  testAsync("takes the origins it's given instead of its own", async t => {
    let allowing = RpcServer.router([smallHandler], ~origins=["http://app.test"])
    let call = from => {
      let headers = rpcHeaders()
      headers->Dict.set("origin", from)
      allowing->RpcServer.respond(
        makeRequest(`${origin}/_weft/rpc/notes.small`, {method: "POST", headers, body: `"a"`}),
        ~id="notes.small",
      )
    }
    t->expect(status(await call("http://app.test")))->Expect.toBe(200)
    t->expect(status(await call(origin)))->Expect.toBe(403)
  })

  testAsync("refuses a body over the limit: the router's, or the RPC's own", async t => {
    let big = `{"noteId": "1", "text": "${String.repeat("x", 70000)}"}`
    t->expect(status(await post(big)))->Expect.toBe(413)
    // Said so up front.
    let headers = rpcHeaders()
    headers->Dict.set("content-length", "1000000")
    t->expect(status(await post(~headers, `{"noteId": "1", "text": "hi"}`)))->Expect.toBe(413)
    t->expect(status(await post(~id="notes.small", `"just over"`)))->Expect.toBe(413)
    t->expect(status(await post(~id="notes.small", `"under"`)))->Expect.toBe(200)
    t->expect(calls)->Expect.toEqual([])
  })

  testAsync("refuses a body that isn't UTF-8", async t => {
    let bytes = Uint8Array.fromArray([0x22, 0xff, 0xfe, 0x22])
    let request = %raw(`(origin, headers, body) =>
      new Request(origin + "/_weft/rpc/notes.small", {method: "POST", headers, body})`)
    let response = await router->RpcServer.respond(
      request(origin, rpcHeaders(), bytes),
      ~id="notes.small",
    )
    t->expect(status(response))->Expect.toBe(400)
  })

  testAsync(
    "answers a handler that throws with a 500 and an error row, through onError",
    async t => {
      let response = await post(`{"noteId": "1", "text": "throw"}`)
      t->expect(status(response))->Expect.toBe(500)
      t
      ->expect(await rowsOf(response))
      ->Expect.toEqual([`0:X{"digest":"digest-1","message":"the database is down"}`])
      t->expect(digests)->Expect.toEqual(["the database is down"])
    },
  )

  test("fails when it's made with two handlers for one ID", t => {
    t
    ->expect(() => RpcServer.router([smallHandler, addCommentHandler, smallHandler]))
    ->Expect.toThrowError(
      ~message="WeftServer: the router has two handlers for the RPC notes.small",
    )
  })

  test("lists its IDs", t => {
    t
    ->expect(RpcServer.ids(router))
    ->Expect.toEqual(["notes.addComment", "notes.later", "notes.render", "notes.small"])
  })
})

describe("IDs", () => {
  test("are names separated by dots", t => {
    ["notes.addComment", "Billing.refund", "a", "a_1.b2.C"]->Array.forEach(
      id => t->expect(Rpc.isValidId(id))->Expect.toBe(true),
    )
    [
      "",
      ".",
      "a.",
      ".a",
      "a..b",
      "1a",
      "_a",
      "a-b",
      "a/b",
      "__proto__",
      "a b",
      "notes.add comment",
    ]->Array.forEach(id => t->expect(Rpc.isValidId(id))->Expect.toBe(false))
  })

  test("that aren't fail Rpc.make", t => {
    t
    ->expect(() => Rpc.make(~id="../admin", ~request=Codec.string))
    ->Expect.toThrowError(~message=`WeftServer: "../admin" isn't an RPC ID`)
  })
})

/** A seeded Lehmer PRNG (as in `Fuzz_test`), so failures reproduce. */
module Random = {
  type t = ref<float>
  let make = (seed: float): t => ref(seed)
  let next = (state: t): float => {
    let product = state.contents *. 48271.0
    state := product -. 2147483647.0 *. Math.floor(product /. 2147483647.0)
    state.contents
  }
  let intBelow = (state: t, bound: int): int => mod(Float.toInt(next(state)), bound)
  let pick = (state: t, items: array<'a>): 'a =>
    items->Array.getUnsafe(intBelow(state, Array.length(items)))
}

let defineField: (dict<JSON.t>, string, JSON.t) => unit = %raw(`(object, name, value) => {
  Object.defineProperty(object, name, {value, writable: true, enumerable: true, configurable: true})
}`)

let names = ["noteId", "text", "__proto__", "constructor", "prototype", "toString", "kind", "x"]

let rec randomJson = (random, ~depth): JSON.t =>
  switch Random.intBelow(random, depth <= 0 ? 5 : 7) {
  | 0 => JSON.Null
  | 1 => JSON.Boolean(Random.intBelow(random, 2) == 0)
  | 2 => JSON.Number(Random.pick(random, [0., 1., -1., 1.5, 1e300, 2147483648.]))
  | 3 | 4 =>
    JSON.String(Random.pick(random, ["", "1", "hi", "throw", "__proto__", String.repeat("x", 30)]))
  | 5 =>
    JSON.Array(
      Array.fromInitializer(~length=Random.intBelow(random, 4), _ =>
        randomJson(random, ~depth=depth - 1)
      ),
    )
  | _ =>
    let fields = Dict.make()
    for _ in 1 to Random.intBelow(random, 4) {
      defineField(fields, Random.pick(random, names), randomJson(random, ~depth=depth - 1))
    }
    JSON.Object(fields)
  }

/** Text that's mostly not JSON: random characters, and JSON cut short. */
let randomText = random =>
  switch Random.intBelow(random, 3) {
  | 0 =>
    Array.fromInitializer(~length=Random.intBelow(random, 40), _ =>
      String.fromCharCode(Random.intBelow(random, 128))
    )->Array.join("")
  | 1 =>
    let json = JSON.stringify(randomJson(random, ~depth=3))
    json->String.slice(~start=0, ~end=Random.intBelow(random, String.length(json) + 1))
  | _ => JSON.stringify(randomJson(random, ~depth=4))
  }

describe("fuzzed", () => {
  beforeEach(resetCalls)

  testAsync(
    "random bodies never crash the router, get a 5xx, or reach a handler unread",
    async t => {
      let ids = ["notes.addComment", "notes.later", "notes.render", "notes.small", "nope"]
      for seed in 1 to 400 {
        let random = Random.make(Int.toFloat(seed))
        let id = Random.pick(random, ids)
        let body = randomText(random)
        let before = Array.length(calls)
        let response = await post(~id, body)
        let status = status(response)
        // The handler throwing ("throw") is the only 5xx, and only for a request it was given.
        let threw = Array.length(calls) > before && (calls->Array.getUnsafe(before)).text == "throw"
        if status >= 500 && !threw {
          JsError.throwWithMessage(
            `seed ${Int.toString(seed)}: ${Int.toString(status)} for ${body}`,
          )
        }

        // A handler is called only with what its codec reads from the body, and `check` accepts.
        if Array.length(calls) > before {
          let call = calls->Array.getUnsafe(before)
          switch JSON.parseOrThrow(body)->Codec.decode(commentCodec, _) {
          | Ok(expected) => t->expect(call)->Expect.toEqual(expected)
          | Error(message) =>
            JsError.throwWithMessage(`seed ${Int.toString(seed)}: called with ${body}: ${message}`)
          }
          t->expect(String.length(call.text) <= 20)->Expect.toBe(true)
        }
        let _ = await text(response)
      }
    },
  )
})

// Calls, through the router in process

/** Requests the fake `fetch` got, by URL. */
let fetched: array<string> = []

/** Whether the fake `fetch` fails as the network would. */
let offline = ref(false)

type fetchInit = {
  method: string,
  headers: dict<string>,
  body: string,
  signal?: Streams.Signal.t,
}

let rejectWith: string => promise<
  Response.t,
> = %raw(`message => Promise.reject(new Error(message))`)
let errorWith: string => exn = %raw(`message => new Error(message)`)

let fakeFetch = (url: string, init: fetchInit) => {
  fetched->Array.push(url)
  if offline.contents {
    rejectWith("offline")
  } else {
    let id = url->String.split("/")->Array.at(-1)->Option.getOr("")
    let response = router->RpcServer.respond(
      makeRequest(
        `${origin}${url}`,
        {
          method: init.method,
          headers: init.headers,
          body: init.body,
          signal: ?init.signal,
        },
      ),
      ~id,
    )
    // As `fetch` does: rejecting once the signal aborts, whatever the server's doing.
    switch init.signal {
    | Some(signal) =>
      Promise.race([
        response,
        Promise.make((_, reject) =>
          signal->Streams.Signal.onAbort(() => reject(errorWith("aborted")), {once: true})
        ),
      ])
    | None => response
    }
  }
}

let globalFetch: unknown = %raw(`globalThis.fetch`)
let setFetch: unknown => unit = %raw(`fetch => { globalThis.fetch = fetch }`)
external toUnknown: 'a => unknown = "%identity"

let call = (rpc, ~signal=?, input) => Rpc.call(rpc, ~client=makeClient(), input, ~signal?)

describe("calls", () => {
  beforeEach(() => {
    resetCalls()
    fetched->Array.splice(~start=0, ~remove=Array.length(fetched), ~insert=[])
    offline := false
    setFetch(toUnknown(fakeFetch))
  })
  afterEach(() => setFetch(globalFetch))

  testAsync("send the request, and give back the response", async t => {
    t->expect(await call(addComment, {noteId: "1", text: "hi"}))->Expect.toEqual(Ok("saved hi"))
    t->expect(fetched)->Expect.toEqual(["/_weft/rpc/notes.addComment"])
    t
    ->expect(await call(addComment, {noteId: "missing", text: "hi"}))
    ->Expect.toEqual(Error(Rpc.Rejected(NoSuchNote)))
  })

  testAsync("send nothing when check or prepare says no", async t => {
    t
    ->expect(await call(addComment, {noteId: "1", text: "this is far too long to be a comment"}))
    ->Expect.toEqual(Error(Rpc.Rejected(TooLong)))
    let prepared: Rpc.t<string, comment, string, commentError> = Rpc.makePrepared(
      ~id="notes.addComment",
      ~request=commentCodec,
      ~prepare=async text =>
        switch String.trim(text) {
        | "" => Error(Empty)
        | text => Ok({noteId: "1", text})
        },
    )
    t->expect(await call(prepared, "   "))->Expect.toEqual(Error(Rpc.Rejected(Empty)))
    t->expect(fetched)->Expect.toEqual([])
    t->expect(await call(prepared, "  hi "))->Expect.toEqual(Ok("saved hi"))
    t->expect(calls)->Expect.toEqual([{noteId: "1", text: "hi"}])
  })

  testAsync("are Invalid when the server can't read the request", async t => {
    // A client whose codec doesn't match the server's: an older one, say.
    let older: Rpc.t<string, string, string, commentError> = Rpc.make(
      ~id="notes.addComment",
      ~request=Codec.string,
    )
    t
    ->expect(await call(older, "hi"))
    ->Expect.toEqual(Error(Rpc.Invalid("the request: expected an object, got a string")))
    t->expect(calls)->Expect.toEqual([])
  })

  testAsync("are Failed for an unknown RPC, the network, and a handler that threw", async t => {
    let unknown: Rpc.t<string, string, unit, unit> = Rpc.make(
      ~id="notes.gone",
      ~request=Codec.string,
    )
    switch await call(unknown, "a") {
    | Error(Rpc.Failed({status, digest: None})) => t->expect(status)->Expect.toEqual(Some(404))
    | _ => JsError.throwWithMessage("expected a 404")
    }
    switch await call(addComment, {noteId: "1", text: "throw"}) {
    | Error(Rpc.Failed({status, digest, message})) =>
      t->expect(status)->Expect.toEqual(Some(500))
      t->expect(digest)->Expect.toEqual(Some("digest-1"))
      t
      ->expect(message)
      ->Expect.toBe("WeftServer: the RPC notes.addComment failed: the database is down")
    | _ => JsError.throwWithMessage("expected a failure")
    }
    offline := true
    switch await call(addComment, {noteId: "1", text: "hi"}) {
    | Error(Rpc.Failed({status: None, message})) =>
      t
      ->expect(message)
      ->Expect.toBe("WeftServer: calling the RPC notes.addComment failed: offline")
    | _ => JsError.throwWithMessage("expected a network failure")
    }
  })

  testAsync("that are aborted are Failed, and abort the handler's request", async t => {
    let controller = Streams.Controller.make()
    let result = call(
      addComment,
      {noteId: "1", text: "wait"},
      ~signal=Streams.Controller.signal(controller),
    )
    await Testing.tick()
    t->expect(Array.length(calls))->Expect.toBe(1)
    controller->Streams.Controller.abort
    switch await result {
    | Error(Rpc.Failed({status: None})) => ()
    | _ => JsError.throwWithMessage("expected the call to fail")
    }
    t->expect(sawAbort.contents)->Expect.toBe(true)
    gate.contents.resolve()
  })

  testAsync("can answer with elements, server components and entrypoints rendered", async t => {
    switch await call(render, "c1") {
    | Ok(element) =>
      let renderer = TestRenderer.create()
      TestRenderer.render(renderer, element)
      await settle()
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe(`<div id="c1"><b id="c1">c1:0</b></div>`)
    | _ => JsError.throwWithMessage("expected an element")
    }
  })

  testAsync("can answer with promises, which stream in after the response", async t => {
    switch await call(later, "note") {
    | Ok({label, later}) =>
      t->expect(label)->Expect.toBe("note")
      gate.contents.resolve()
      t->expect(await later)->Expect.toBe("note, later")
    | _ => JsError.throwWithMessage("expected a response")
    }
  })
})
