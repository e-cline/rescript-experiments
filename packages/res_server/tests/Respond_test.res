open Vitest

let contentType = (response: Response.t): option<string> => TestSupport.contentType(response)

/** A `next` function yielding each of `values` in turn, then `None`, with a count of its calls. */
let source = (values: array<'value>): (unit => promise<option<'value>>, ref<int>) => {
  let calls = ref(0)
  let next = async () => {
    let value = values->Array.get(calls.contents)
    calls := calls.contents + 1
    value
  }
  (next, calls)
}

describe("Respond", () => {
  testAsync("text", async t => {
    let response = Respond.text("hello")
    t->expect(response.status)->Expect.toBe(200)
    t->expect(response->contentType)->Expect.toEqual(Some("text/plain; charset=utf-8"))
    t->expect(await response->Response.text)->Expect.toBe("hello")
  })

  testAsync("html", async t => {
    let response = Respond.html(Html.html`<h1>${Html.text("a < b")}</h1>`)
    t->expect(response->contentType)->Expect.toEqual(Some("text/html; charset=utf-8"))
    t->expect(await response->Response.text)->Expect.toBe("<h1>a &lt; b</h1>")
  })

  testAsync("json", async t => {
    let data = JSON.Encode.object(dict{"ok": JSON.Encode.bool(true)})
    let response = Respond.json(~status=201, data)
    t->expect(response.status)->Expect.toBe(201)
    t->expect(response->contentType)->Expect.toEqual(Some("application/json"))
    t->expect(await response->Response.json)->Expect.toEqual(data)
  })

  test("status and extra headers; a given content-type wins", t => {
    let response = Respond.text(
      ~status=418,
      ~headers=dict{"X-Kind": "teapot", "Content-Type": "text/teapot"},
      "short and stout",
    )
    t->expect(response.status)->Expect.toBe(418)
    t->expect(response.headers->HttpHeaders.get("x-kind"))->Expect.toEqual(Some("teapot"))
    t->expect(response->contentType)->Expect.toEqual(Some("text/teapot"))
  })

  testAsync("empty, redirect and notFound", async t => {
    let empty = Respond.empty()
    t->expect(empty.status)->Expect.toBe(204)
    t->expect(empty.body)->Expect.toEqual(Null.null)

    let redirect = Respond.redirect("/login?next=%2F")
    t->expect(redirect.status)->Expect.toBe(302)
    t
    ->expect(redirect.headers->HttpHeaders.get("location"))
    ->Expect.toEqual(Some("/login?next=%2F"))
    t->expect(Respond.redirect(~status=308, "/new").status)->Expect.toBe(308)

    let notFound = Respond.notFound()
    t->expect(notFound.status)->Expect.toBe(404)
    t->expect(await notFound->Response.text)->Expect.toBe("Not Found")
  })

  test("withHeader", t => {
    let response = Respond.text("x")->Respond.withHeader("Cache-Control", "no-store")
    t->expect(response.headers->HttpHeaders.get("cache-control"))->Expect.toEqual(Some("no-store"))
  })

  testAsync("withHeader copies a response whose headers are read-only", async t => {
    let readOnly = Response.redirect(~url="http://example.test/next", ~status=307)
    let response = readOnly->Respond.withHeader("X-Extra", "yes")
    t->expect(response.status)->Expect.toBe(307)
    t->expect(response.headers->HttpHeaders.get("x-extra"))->Expect.toEqual(Some("yes"))
    t
    ->expect(response.headers->HttpHeaders.get("location"))
    ->Expect.toEqual(Some("http://example.test/next"))

    // The same, for one with a body: it's kept, as are the status and headers.
    let fetched = await Fetch.fetch("data:text/plain,hello")
    let response = fetched->Respond.withHeader("X-Extra", "yes")
    t->expect(response.headers->HttpHeaders.get("x-extra"))->Expect.toEqual(Some("yes"))
    t->expect(response->contentType)->Expect.toEqual(fetched->contentType)
    t->expect(await response->Response.text)->Expect.toBe("hello")
  })

  test("withHeaders calls its function once, and passes on what it throws", t => {
    let runs = ref(0)
    let failing = (response: Response.t) =>
      switch response->Respond.withHeaders(
        _headers => {
          runs := runs.contents + 1
          JsError.throwWithMessage("not about the headers")
        },
      ) {
      | _ => "returned"
      | exception JsExn(error) => error->JsExn.message->Option.getOr("")
      }
    t->expect(failing(Respond.text("x")))->Expect.toBe("not about the headers")
    t->expect(runs.contents)->Expect.toBe(1)
    // The same for a response that has to be copied first.
    t
    ->expect(failing(Response.redirect(~url="http://example.test/next")))
    ->Expect.toBe("not about the headers")
    t->expect(runs.contents)->Expect.toBe(2)
  })

  test("withHeaders leaves no trace of how it found out the headers can be changed", t => {
    let response = Respond.text("x")->Respond.withHeaders(_headers => ())
    t
    ->expect(response.headers->HttpHeaders.toArray)
    ->Expect.toEqual([("content-type", "text/plain; charset=utf-8")])
  })

  test("setCookie adds a Set-Cookie header per cookie", t => {
    let response =
      Respond.text("x")
      ->Respond.setCookie("session", "abc 123")
      ->Respond.setCookie(
        "theme",
        "dark",
        ~options={httpOnly: false, maxAge: 3600, secure: true, sameSite: Strict},
      )
    t
    ->expect(response.headers->Headers.getSetCookie)
    ->Expect.toEqual([
      "session=abc%20123; Path=/; HttpOnly; SameSite=Lax",
      "theme=dark; Path=/; Max-Age=3600; Secure; SameSite=Strict",
    ])
  })

  test("deleteCookie expires the cookie", t => {
    let response = Respond.empty()->Respond.deleteCookie("session")
    t
    ->expect(response.headers->Headers.getSetCookie)
    ->Expect.toEqual([
      "session=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Lax",
    ])
  })

  testAsync("textStream sends each value as its own chunk", async t => {
    let (next, _) = source(["one ", "two ", "three"])
    let response = Respond.textStream(next)
    t->expect(response->contentType)->Expect.toEqual(Some("text/plain; charset=utf-8"))
    t->expect(await response->TestSupport.chunks)->Expect.toEqual(["one ", "two ", "three"])
  })

  testAsync("ndjson sends one line of JSON per value", async t => {
    let values = [1, 2, 3]->Array.map(n => JSON.Encode.object(dict{"n": JSON.Encode.int(n)}))
    let (next, _) = source(values)
    let response = Respond.ndjson(next)
    t->expect(response->contentType)->Expect.toEqual(Some("application/x-ndjson; charset=utf-8"))
    t
    ->expect(await response->TestSupport.chunks)
    ->Expect.toEqual([`{"n":1}\n`, `{"n":2}\n`, `{"n":3}\n`])
  })

  testAsync("an ndjson body read whole parses line by line", async t => {
    let values = [JSON.Encode.string("a\nb"), JSON.Encode.null]
    let (next, _) = source(values)
    let body = await Respond.ndjson(next)->Response.text
    t
    ->expect(body->String.trim->String.split("\n")->Array.map(line => JSON.parseOrThrow(line)))
    ->Expect.toEqual(values)
  })

  testAsync("toTextChunks keeps a character whole when its bytes span two chunks", async t => {
    let encoded = ByteStream.Encoder.make()->ByteStream.Encoder.encode("aé")
    let parts = [encoded->TypedArray.slice(~start=0, ~end=2), encoded->TypedArray.slice(~start=2)]
    let (next, _) = source(parts)
    let chunks = await ByteStream.fromPull(next)->ByteStream.toTextChunks
    t->expect(chunks)->Expect.toEqual(["a", "é"])
    t->expect(chunks->Array.join(""))->Expect.toBe("aé")
  })

  testAsync("a stream with no values is an empty body", async t => {
    let (next, _) = source([])
    t->expect(await Respond.ndjson(next)->Response.text)->Expect.toBe("")
  })

  testAsync("a stream is pulled only as it's read, and not after it's cancelled", async t => {
    let (next, calls) = source(["a", "b", "c", "d", "e"])
    let endings = []
    let response = Respond.textStream(~onEnd=ending => endings->Array.push(ending), next)
    switch response.body->Null.toOption {
    | None => t->expect("no body")->Expect.toBe("a body")
    | Some(body) =>
      let reader = body->ByteStream.fromBody->ByteStream.getReader
      let _ = await reader->ByteStream.Reader.read
      let _ = await reader->ByteStream.Reader.read
      // Two chunks read, plus at most one waiting in the stream's queue.
      t->expect(calls.contents)->Expect.Int.toBeLessThanOrEqual(3)
      await reader->ByteStream.Reader.cancel
      let callsAtCancel = calls.contents
      await Promise.make((resolve, _) => setTimeout(() => resolve(), 20)->ignore)
      t->expect(calls.contents)->Expect.toBe(callsAtCancel)
    }
    t->expect(endings)->Expect.toEqual([ByteStream.Cancelled])
  })

  testAsync("onEnd is told when a stream runs to its end", async t => {
    let (next, _) = source(["a", "b"])
    let endings = []
    let response = Respond.textStream(~onEnd=ending => endings->Array.push(ending), next)
    // Not before it's over.
    t->expect(endings)->Expect.toEqual([])
    t->expect(await response->Response.text)->Expect.toBe("ab")
    t->expect(endings)->Expect.toEqual([ByteStream.Completed])
  })

  testAsync("onEnd is told when producing a value fails, and the reader finds out", async t => {
    let sent = ref(0)
    let endings = []
    let response = Respond.ndjson(
      ~onEnd=ending => endings->Array.push(ending),
      async () => {
        sent := sent.contents + 1
        if sent.contents == 3 {
          JsError.throwWithMessage("cursor failed")
        }
        Some(JSON.Encode.int(sent.contents))
      },
    )
    let outcome = switch await response->Response.text {
    | body => `read all of ${body}`
    | exception JsExn(error) => error->JsExn.message->Option.getOr("")
    }
    t->expect(outcome)->Expect.toBe("cursor failed")
    t
    ->expect(
      endings->Array.map(
        ending =>
          switch ending {
          | ByteStream.Failed(JsExn(error)) => error->JsExn.message->Option.getOr("")
          | Failed(_) => "failed"
          | Completed => "completed"
          | Cancelled => "cancelled"
          },
      ),
    )
    ->Expect.toEqual(["cursor failed"])
    // And the source isn't asked again.
    t->expect(sent.contents)->Expect.toBe(3)
  })

  testAsync("withoutBody keeps the status and headers, and stops a streamed body", async t => {
    let plain = Respond.text(~status=201, ~headers=dict{"x-a": "1"}, "body")->Respond.withoutBody
    t->expect(plain.status)->Expect.toBe(201)
    t->expect(plain.headers->HttpHeaders.get("x-a"))->Expect.toEqual(Some("1"))
    t->expect(plain->contentType)->Expect.toEqual(Some("text/plain; charset=utf-8"))
    t->expect(await plain->Response.text)->Expect.toBe("")

    let (next, calls) = source(["a", "b", "c"])
    let endings = []
    let streamed =
      Respond.textStream(~onEnd=ending => endings->Array.push(ending), next)->Respond.withoutBody
    t->expect(await streamed->Response.text)->Expect.toBe("")
    await Promise.make((resolve, _) => setTimeout(() => resolve(), 20)->ignore)
    t->expect(endings)->Expect.toEqual([ByteStream.Cancelled])
    t->expect(calls.contents)->Expect.Int.toBeLessThanOrEqual(1)

    let empty = Respond.empty()
    t->expect(empty->Respond.withoutBody)->Expect.toBe(empty)
  })

  test("deleteCookie adds what a prefixed or partitioned cookie needs", t => {
    let cookies = (response: Response.t) => response.headers->Headers.getSetCookie
    t
    ->expect(Respond.empty()->Respond.deleteCookie("__Host-session")->cookies)
    ->Expect.toEqual([
      "__Host-session=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; Secure; SameSite=Lax",
    ])
    t
    ->expect(Respond.empty()->Respond.deleteCookie("widget", ~partitioned=true)->cookies)
    ->Expect.toEqual([
      "widget=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; Secure; SameSite=Lax; Partitioned",
    ])
  })
})
