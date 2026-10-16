/***
End to end: an application served over real HTTP by `NodeServer`, and called
with `fetch`.
*/

open Vitest

let sleep = TestSupport.sleep

let count: Handler.t = async _ctx => {
  let sent = ref(0)
  Respond.ndjson(async () =>
    if sent.contents >= 3 {
      None
    } else {
      // Spaced out so that each line is its own chunk on the wire.
      await sleep(30)
      sent := sent.contents + 1
      Some(JSON.Encode.int(sent.contents))
    }
  )
}

let routes: array<Route.t> = [
  Route.post(list{"login"}, async _ctx =>
    Respond.empty()->Respond.setCookie("session", "s3cr3t")->Respond.setCookie("seen", "yes")
  ),
  Route.get(list{"whoami"}, async ctx =>
    Respond.text(ctx->RequestContext.cookie("session")->Option.getOr("nobody"))
  ),
  Route.get(list{"hello", ":name"}, async ctx =>
    Respond.text(`Hello, ${ctx->RequestContext.paramOrThrow("name")}!`)
  ),
  Route.post(list{"echo"}, async ctx =>
    switch await ctx->RequestContext.json {
    | Ok(json) => Respond.json(json)
    | Error(error) => Respond.text(~status=400, RequestContext.bodyErrorMessage(error))
    }
  ),
  Route.get(list{"count"}, count),
  Route.get(list{"old"}, async _ctx => Respond.redirect("/hello/redirected")),
]

// Put together from the outside in: the CORS middleware goes around the router.
let app: App.t =
  App.build()
  ->App.use(Cors.middleware(~origins=Only(["https://app.example"])))
  ->App.router(routes)

/** A Node system error's code, like `EADDRINUSE`. */
@get
external errorCode: JsExn.t => string = "code"

/** Runs `f` with the base URL of `app` being served on a free port. */
let withServer = async (f: string => promise<'result>): 'result => {
  let (server, address) = await NodeServer.listen(~port=0, ~hostname="127.0.0.1", app)
  let result = try Ok(await f(`http://127.0.0.1:${address.port->Int.toString}`)) catch {
  | error => Error(error)
  }
  await server->NodeServer.close
  switch result {
  | Ok(value) => value
  | Error(error) => throw(error)
  }
}

describe("NodeServer", () => {
  testAsync("serves an application over HTTP", async t =>
    await withServer(
      async base => {
        let response = await Fetch.fetch(`${base}/hello/Grace%20Hopper`)
        t->expect(response.status)->Expect.toBe(200)
        t
        ->expect(response->TestSupport.contentType)
        ->Expect.toEqual(Some("text/plain; charset=utf-8"))
        t->expect(await response->Response.text)->Expect.toBe("Hello, Grace Hopper!")

        let response = await Fetch.fetch(`${base}/nope`)
        t->expect(response.status)->Expect.toBe(404)
      },
    )
  )

  testAsync("passes on the request's method, headers and body", async t =>
    await withServer(
      async base => {
        let post = body =>
          Fetch.fetch(
            `${base}/echo`,
            ~init={
              method: "POST",
              headers: HeadersInit.fromDict(dict{"content-type": "application/json"}),
              body: BodyInit.fromString(body),
            },
          )
        let response = await post(`{"n":[1,2,3]}`)
        t->expect(await response->Response.json)->Expect.toEqual(JSON.parseOrThrow(`{"n":[1,2,3]}`))
        t->expect((await post("{nope")).status)->Expect.toBe(400)
      },
    )
  )

  testAsync("streams a response chunk by chunk", async t =>
    await withServer(
      async base => {
        let response = await Fetch.fetch(`${base}/count`)
        t->expect(await response->TestSupport.chunks)->Expect.toEqual(["1\n", "2\n", "3\n"])
      },
    )
  )

  testAsync("follows a relative redirect", async t =>
    await withServer(
      async base => {
        let response = await Fetch.fetch(`${base}/old`)
        t->expect(await response->Response.text)->Expect.toBe("Hello, redirected!")
      },
    )
  )

  testAsync("sets cookies, and reads the ones sent back", async t =>
    await withServer(
      async base => {
        let response = await Fetch.fetch(`${base}/login`, ~init={method: "POST"})
        t
        ->expect(response.headers->Headers.getSetCookie)
        ->Expect.toEqual([
          "session=s3cr3t; Path=/; HttpOnly; SameSite=Lax",
          "seen=yes; Path=/; HttpOnly; SameSite=Lax",
        ])

        let whoami = cookie =>
          Fetch.fetch(`${base}/whoami`, ~init={headers: HeadersInit.fromDict(cookie)})
        t
        ->expect(await (await whoami(dict{"cookie": "seen=yes; session=s3cr3t"}))->Response.text)
        ->Expect.toBe("s3cr3t")
        t->expect(await (await whoami(dict{}))->Response.text)->Expect.toBe("nobody")
      },
    )
  )

  testAsync("answers a CORS preflight, and marks the response that follows", async t =>
    await withServer(
      async base => {
        let origin = dict{"origin": "https://app.example"}
        let preflight = await Fetch.fetch(
          `${base}/echo`,
          ~init={
            method: "OPTIONS",
            headers: HeadersInit.fromDict(
              dict{
                "origin": "https://app.example",
                "access-control-request-method": "POST",
                "access-control-request-headers": "content-type",
              },
            ),
          },
        )
        let header = (response: Response.t, name) => response.headers->HttpHeaders.get(name)
        t->expect(preflight.status)->Expect.toBe(204)
        t
        ->expect(preflight->header("access-control-allow-origin"))
        ->Expect.toEqual(Some("https://app.example"))
        t
        ->expect(preflight->header("access-control-allow-headers"))
        ->Expect.toEqual(Some("content-type"))

        let response = await Fetch.fetch(
          `${base}/hello/Ada`,
          ~init={headers: HeadersInit.fromDict(origin)},
        )
        t
        ->expect(response->header("access-control-allow-origin"))
        ->Expect.toEqual(Some("https://app.example"))
        t->expect(await response->Response.text)->Expect.toBe("Hello, Ada!")
      },
    )
  )

  testAsync("run serves an application built in one pipe", async t => {
    let listening = ref(None)
    let server =
      NodeServer.run(
        ~port=0,
        ~hostname="127.0.0.1",
        ~onListen=address => listening := Some(address.port),
      )
      ->App.use(Middleware.responseHeaders(dict{"x-served-by": "run"}))
      ->App.router(routes)
    // `onListen` is called once the server is accepting connections.
    while listening.contents->Option.isNone {
      await sleep(5)
    }
    let port = listening.contents->Option.getOr(0)
    let response = await Fetch.fetch(`http://127.0.0.1:${port->Int.toString}/hello/Ada`)
    let body = await response->Response.text
    await server->NodeServer.close
    t->expect(body)->Expect.toBe("Hello, Ada!")
    t->expect(response.headers->HttpHeaders.get("x-served-by"))->Expect.toEqual(Some("run"))
  })

  testAsync("refuses a path with an encoded separator, over HTTP", async t =>
    await withServer(
      async base => {
        let response = await Fetch.fetch(`${base}/hello/..%2F..%2Fetc%2Fpasswd`)
        t->expect(response.status)->Expect.toBe(400)
        // Still inside the middleware: the CORS middleware marked it.
        t->expect(response.headers->HttpHeaders.get("vary"))->Expect.toEqual(Some("Origin"))
      },
    )
  )

  testAsync("listen is rejected when the port is in use", async t =>
    await withServer(
      async base => {
        let port =
          base->String.split(":")->Array.at(-1)->Option.flatMap(port => Int.fromString(port))
        let outcome = switch await NodeServer.listen(~port?, ~hostname="127.0.0.1", app) {
        | (server, _address) =>
          await server->NodeServer.close
          "listening"
        | exception JsExn(error) => error->errorCode
        }
        t->expect(outcome)->Expect.toBe("EADDRINUSE")
      },
    )
  )

  testAsync("serve reports a failure to listen to onServerError", async t =>
    await withServer(
      async base => {
        let port =
          base->String.split(":")->Array.at(-1)->Option.flatMap(port => Int.fromString(port))
        let failure = await Promise.make(
          (resolve, _reject) => {
            let _ = NodeServer.serve(
              ~port?,
              ~hostname="127.0.0.1",
              ~onServerError=error => resolve(error->errorCode),
              app,
            )
          },
        )
        t->expect(failure)->Expect.toBe("EADDRINUSE")
      },
    )
  )

  testAsync("listens on this machine only, unless told otherwise", async t => {
    let (server, address) = await NodeServer.listen(~port=0, app)
    await server->NodeServer.close
    t->expect(address.address)->Expect.toBe("127.0.0.1")
  })

  testAsync("answers HEAD from a GET route, and 405 for a method a path doesn't take", async t =>
    await withServer(
      async base => {
        let head = await Fetch.fetch(`${base}/hello/Ada`, ~init={method: "HEAD"})
        t->expect(head.status)->Expect.toBe(200)
        t->expect(head->TestSupport.contentType)->Expect.toEqual(Some("text/plain; charset=utf-8"))
        t->expect(await head->Response.text)->Expect.toBe("")

        let wrong = await Fetch.fetch(`${base}/hello/Ada`, ~init={method: "DELETE"})
        t->expect(wrong.status)->Expect.toBe(405)
        t
        ->expect(wrong.headers->HttpHeaders.get("allow"))
        ->Expect.toEqual(Some("GET, HEAD, OPTIONS"))
      },
    )
  )

  testAsync("listens where it's told to", async t => {
    let (server, address) = await NodeServer.listen(~port=0, ~hostname="0.0.0.0", app)
    let response = await Fetch.fetch(`http://127.0.0.1:${address.port->Int.toString}/hello/Ada`)
    let body = await response->Response.text
    await server->NodeServer.close
    t->expect(address.address)->Expect.toBe("0.0.0.0")
    t->expect(body)->Expect.toBe("Hello, Ada!")
  })

  testAsync(
    "a stream that fails part-way ends the response, and the server carries on",
    async t => {
      let endings = []
      let failing: Handler.t = async _ctx => {
        let sent = ref(0)
        Respond.ndjson(
          ~onEnd=ending => endings->Array.push(ending),
          async () => {
            sent := sent.contents + 1
            if sent.contents == 2 {
              JsError.throwWithMessage("cursor failed")
            }
            await sleep(20)
            Some(JSON.Encode.int(sent.contents))
          },
        )
      }
      let app =
        App.build()->App.router([
          Route.get(list{"fails"}, failing),
          Route.get(list{"ok"}, async _ctx => Respond.text("ok")),
        ])
      let (server, address) = await NodeServer.listen(~port=0, app)
      let base = `http://127.0.0.1:${address.port->Int.toString}`
      // The failure is logged by the server; that's expected here.
      let ((status, outcome), _logged) = await TestSupport.countingConsoleErrors(
        async () => {
          let response = await Fetch.fetch(`${base}/fails`)
          let outcome = switch await response->Response.text {
          | body => `complete: ${body}`
          | exception _ => "cut short"
          }
          (response.status, outcome)
        },
      )
      let after = await (await Fetch.fetch(`${base}/ok`))->Response.text
      await server->NodeServer.close
      // The status had gone out before the failure, so it can't become a 500:
      // the client finds out by the body ending early.
      t->expect(status)->Expect.toBe(200)
      t->expect(outcome)->Expect.toBe("cut short")
      t->expect(after)->Expect.toBe("ok")
      t
      ->expect(
        endings->Array.map(
          ending =>
            switch ending {
            | ByteStream.Failed(_) => "failed"
            | Completed => "completed"
            | Cancelled => "cancelled"
            },
        ),
      )
      ->Expect.toEqual(["failed"])
    },
  )

  testAsync("close waits for a response that is still being streamed", async t => {
    let (server, address) = await NodeServer.listen(~port=0, app)
    let response = await Fetch.fetch(`http://127.0.0.1:${address.port->Int.toString}/count`)
    // The response has started; ask the server to stop while it's going.
    let closed = ref(false)
    let closing = server->NodeServer.close->Promise.thenResolve(() => closed := true)
    let closedBeforeTheEnd = closed.contents
    let body = await response->Response.text
    await closing
    t->expect(closedBeforeTheEnd)->Expect.toBe(false)
    t->expect(body)->Expect.toBe("1\n2\n3\n")
    t->expect(closed.contents)->Expect.toBe(true)
    // And it takes no new connections.
    let refused = switch await Fetch.fetch(`http://127.0.0.1:${address.port->Int.toString}/count`) {
    | _ => false
    | exception _ => true
    }
    t->expect(refused)->Expect.toBe(true)
  })
})
