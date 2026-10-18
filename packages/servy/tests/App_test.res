open Vitest

let ownerKey: Context.Key.t<string> = Context.Key.make(~name="owner")

let routes: Handler.t = Router.make([
  Route.get(list{}, async ctx =>
    Respond.text(`home of ${ctx->RequestContext.getOrThrow(ownerKey)}`)
  ),
  Route.get(list{"users", ":id"}, async ctx =>
    Respond.text(`user ${ctx->RequestContext.paramOrThrow("id")}`)
  ),
  Route.post(list{"users"}, async ctx => Respond.text(~status=201, await ctx->RequestContext.text)),
  Route.get(list{"search"}, async ctx =>
    Respond.text(ctx.query->Query.getInt("page")->Option.getOr(1)->Int.toString)
  ),
  Route.get(list{"throws"}, async _ctx => JsError.throwWithMessage("boom")),
])

let onError = (_error: exn, request: Request.t): Response.t =>
  Respond.text(~status=500, `failed: ${request.method}`)

// The whole application, set up as one pipe.
// Put together from the outside in: the middleware first, then what it goes around.
let app: App.t =
  App.build(~onError)->App.use(Middleware.provide(ownerKey, "Ada"))->App.handle(routes)

let get = async (path: string): (int, string) => {
  let response = await app(TestSupport.request(path))
  (response.status, await response->Response.text)
}

describe("App", () => {
  testAsync("turns a handler into a function from Request to Response", async t => {
    t->expect(await get("/"))->Expect.toEqual((200, "home of Ada"))
    t->expect(await get("/users/42"))->Expect.toEqual((200, "user 42"))
    t->expect(await get("/users/a%20b"))->Expect.toEqual((200, "user a b"))
    t->expect(await get("/search?page=3"))->Expect.toEqual((200, "3"))
    t->expect(await get("/nope"))->Expect.toEqual((404, "Not Found"))

    let response = await app(TestSupport.request(~method="POST", ~body="new user", "/users"))
    t->expect(response.status)->Expect.toBe(201)
    t->expect(await response->Response.text)->Expect.toBe("new user")
  })

  testAsync("onError answers when a handler throws", async t => {
    t->expect(await get("/throws"))->Expect.toEqual((500, "failed: GET"))
  })

  testAsync("onError answers when a handler's promise rejects", async t => {
    let rejects: Handler.t = _ctx => Promise.reject(Failure("boom"))
    let app =
      rejects->App.make(~onError=(_error, _request) => Respond.text(~status=503, "rejected"))
    let response = await app(TestSupport.request("/"))
    t->expect(response.status)->Expect.toBe(503)
  })

  testAsync("onError answers when a handler needs a value no middleware attached", async t => {
    // The same routes, without the middleware that provides `ownerKey`.
    let app = routes->App.make(~onError=(_error, _request) => Respond.text(~status=500, "failed"))
    let response = await app(TestSupport.request("/"))
    t->expect(response.status)->Expect.toBe(500)
    // Routes that don't need it are unaffected.
    let response = await app(TestSupport.request("/users/42"))
    t->expect(response.status)->Expect.toBe(200)
  })

  testAsync("the first middleware used is the outermost", async t => {
    let log = []
    let tracing = (name: string): Middleware.t =>
      next =>
        async ctx => {
          log->Array.push(`${name} before`)
          let response = await next(ctx)
          log->Array.push(`${name} after`)
          response
        }
    let handler: Handler.t = async _ctx => {
      log->Array.push("handler")
      Respond.text("ok")
    }
    let app = App.build()->App.use(tracing("a"))->App.use(tracing("b"))->App.handle(handler)
    let _ = await app(TestSupport.request("/"))
    t->expect(log)->Expect.toEqual(["a before", "b before", "handler", "b after", "a after"])
  })

  testAsync("using each middleware in turn is using their pipeline", async t => {
    let run = async (build: (string => Middleware.t) => App.t): array<string> => {
      let log = []
      let tracing = (name: string): Middleware.t =>
        next =>
          async ctx => {
            log->Array.push(name)
            await next(ctx)
          }
      let _ = await build(tracing)(TestSupport.request("/"))
      log
    }
    let ok: Handler.t = async _ctx => Respond.text("ok")
    let separately = await run(m => App.build()->App.use(m("a"))->App.use(m("b"))->App.handle(ok))
    let together = await run(
      m => App.build()->App.use(Middleware.pipeline([m("a"), m("b")]))->App.handle(ok),
    )
    let direct = await run(
      m => App.make(Middleware.pipeline([m("a"), m("b")])->Middleware.apply(ok)),
    )
    t->expect(separately)->Expect.toEqual(["a", "b"])
    t->expect(together)->Expect.toEqual(separately)
    t->expect(direct)->Expect.toEqual(separately)
  })

  testAsync("router finishes with a router for the routes", async t => {
    let app =
      App.build()
      ->App.use(Middleware.responseHeaders(dict{"x-app": "yes"}))
      ->App.router([Route.get(list{"a"}, async _ctx => Respond.text("a"))])
    let response = await app(TestSupport.request("/a"))
    t->expect(await response->Response.text)->Expect.toBe("a")
    t->expect(response.headers->HttpHeaders.get("x-app"))->Expect.toEqual(Some("yes"))
    // The middleware is outside the router, so it sees unmatched requests too.
    let response = await app(TestSupport.request("/nope"))
    t->expect(response.status)->Expect.toBe(404)
    t->expect(response.headers->HttpHeaders.get("x-app"))->Expect.toEqual(Some("yes"))
  })

  testAsync("a builder with nothing used is just the handler", async t => {
    let app = App.build()->App.handle(routes)
    t->expect((await app(TestSupport.request("/users/1"))).status)->Expect.toBe(200)
  })

  testAsync("an error in a handler is answered inside the middleware", async t => {
    let lines = []
    let app =
      App.build(~onError=(_error, _request) => Respond.text(~status=500, "failed"))
      ->App.use(Middleware.logger(~log=line => lines->Array.push(line)))
      ->App.use(Cors.middleware(~origins=Only(["https://app.example"])))
      ->App.use(Middleware.responseHeaders(dict{"x-frame-options": "DENY"}))
      ->App.router([
        Route.get(list{"ok"}, async _ctx => Respond.text("ok")),
        Route.get(list{"throws"}, async _ctx => JsError.throwWithMessage("boom")),
        Route.get(list{"rejects"}, _ctx => Promise.reject(Failure("boom"))),
      ])
    let ask = async path => {
      let response = await app(
        TestSupport.request(~headers=dict{"Origin": "https://app.example"}, path),
      )
      (
        response.status,
        response.headers->HttpHeaders.get("access-control-allow-origin"),
        response.headers->HttpHeaders.get("x-frame-options"),
      )
    }
    let marked = status => (status, Some("https://app.example"), Some("DENY"))
    t->expect(await ask("/ok"))->Expect.toEqual(marked(200))
    // The 500 is a response like any other to the middleware: it gets their
    // headers, and its line in the log.
    t->expect(await ask("/throws"))->Expect.toEqual(marked(500))
    t->expect(await ask("/rejects"))->Expect.toEqual(marked(500))
    t
    ->expect(lines->Array.map(line => line->String.split(" ")->Array.slice(~start=0, ~end=3)))
    ->Expect.toEqual([["GET", "/ok", "200"], ["GET", "/throws", "500"], ["GET", "/rejects", "500"]])
  })

  testAsync("onError is given the error and the request", async t => {
    let seen = ref(None)
    let app = App.build(
      ~onError=(error, request) => {
        seen :=
          Some((
            switch error {
            | JsExn(error) => error->JsExn.message->Option.getOr("")
            | _ => "not a JS error"
            },
            request.url,
          ))
        Respond.text(~status=500, "failed")
      },
    )->App.handle(async _ctx => JsError.throwWithMessage("boom"))
    let _ = await app(TestSupport.request("/x?y=1"))
    t->expect(seen.contents)->Expect.toEqual(Some(("boom", "http://example.test/x?y=1")))
  })

  testAsync("an error in a middleware is still answered, by onError directly", async t => {
    let lines = []
    let broken: Middleware.t = _next => async _ctx => JsError.throwWithMessage("middleware broke")
    let app =
      App.build(~onError=(_error, _request) => Respond.text(~status=500, "failed"))
      ->App.use(Middleware.logger(~log=line => lines->Array.push(line)))
      ->App.use(broken)
      ->App.use(Middleware.responseHeaders(dict{"x-inner": "yes"}))
      ->App.handle(async _ctx => Respond.text("ok"))
    let response = await app(TestSupport.request("/"))
    t->expect(response.status)->Expect.toBe(500)
    t->expect(await response->Response.text)->Expect.toBe("failed")
    // Nothing inside the middleware that failed ran, and nothing outside it
    // saw a response.
    t->expect(response.headers->HttpHeaders.get("x-inner"))->Expect.toEqual(None)
    t->expect(lines)->Expect.toEqual([])
  })

  testAsync("an onError that throws still gets the client an answer", async t => {
    let broken = (_error, _request) => JsError.throwWithMessage("the error handler broke")
    let handler: Handler.t = async _ctx => JsError.throwWithMessage("boom")
    let ask = async (app: App.t) => {
      let (response, logged) = await TestSupport.countingConsoleErrors(
        () => app(TestSupport.request("/")),
      )
      (response.status, await response->Response.text, logged > 0)
    }
    let plain500 = (500, "Internal Server Error", true)
    t->expect(await ask(App.build(~onError=broken)->App.handle(handler)))->Expect.toEqual(plain500)
    t->expect(await ask(handler->App.make(~onError=broken)))->Expect.toEqual(plain500)
    // From a middleware, too, where onError is the last resort.
    let failing: Middleware.t = _next => async _ctx => JsError.throwWithMessage("middleware broke")
    t
    ->expect(await ask(App.build(~onError=broken)->App.use(failing)->App.handle(handler)))
    ->Expect.toEqual(plain500)
  })

  testAsync("the default onError logs the error and says nothing about it", async t => {
    let app = App.build()->App.handle(async _ctx => JsError.throwWithMessage("a secret detail"))
    let (response, logged) = await TestSupport.countingConsoleErrors(
      () => app(TestSupport.request("/")),
    )
    t->expect(response.status)->Expect.toBe(500)
    t->expect(await response->Response.text)->Expect.toBe("Internal Server Error")
    t->expect(logged)->Expect.toBe(1)
  })

  testAsync("Middleware.recover answers for whatever is inside it, where it's put", async t => {
    let lines = []
    let broken: Middleware.t = _next => async _ctx => JsError.throwWithMessage("middleware broke")
    let app =
      App.build()
      ->App.use(Middleware.logger(~log=line => lines->Array.push(line)))
      ->App.use(Middleware.recover(async (_error, _ctx) => Respond.text(~status=503, "recovered")))
      ->App.use(broken)
      ->App.handle(async _ctx => Respond.text("ok"))
    let response = await app(TestSupport.request("/"))
    t->expect(response.status)->Expect.toBe(503)
    t->expect(lines->Array.length)->Expect.toBe(1)
  })

  testAsync("a request whose path has an unsafe segment is answered 400", async t => {
    let reached = ref(false)
    let lines = []
    let app =
      App.build()
      ->App.use(Middleware.logger(~log=line => lines->Array.push(line)))
      ->App.use(Middleware.responseHeaders(dict{"x-app": "yes"}))
      ->App.router([
        Route.any(
          list{"static", "**"},
          async ctx => {
            reached := true
            Respond.text(ctx.path->List.toArray->Array.join("/"))
          },
        ),
        Route.get(
          list{"files", ":name"},
          async ctx => {
            reached := true
            Respond.text(ctx->RequestContext.paramOrThrow("name"))
          },
        ),
      ])
    let ask = async path => {
      let response = await app(TestSupport.request(path))
      (response.status, await response->Response.text)
    }
    t->expect(await ask("/static/css/site.css"))->Expect.toEqual((200, "css/site.css"))
    t->expect(await ask("/files/report%202024.pdf"))->Expect.toEqual((200, "report 2024.pdf"))
    reached := false

    let unsafe = [
      "/static/..%2F..%2Fetc%2Fpasswd",
      "/static/..%5C..%5Cwindows",
      "/static/a%00b",
      "/files/..%2Fsecret",
      "/files/a%2Fb",
      "/nowhere/a%2Fb",
    ]
    for index in 0 to unsafe->Array.length - 1 {
      t
      ->expect(await ask(unsafe->Array.getUnsafe(index)))
      ->Expect.toEqual((400, "Bad Request"))
    }
    t->expect(reached.contents)->Expect.toBe(false)

    // Refused inside the middleware: logged, and given their headers.
    let response = await app(TestSupport.request("/static/a%2Fb"))
    t->expect(response.headers->HttpHeaders.get("x-app"))->Expect.toEqual(Some("yes"))
    t
    ->expect(lines->Array.filter(line => line->String.includes(" 400 "))->Array.length)
    ->Expect.toBe(7)

    // What the URL parser resolves is not unsafe, just somewhere else.
    t->expect(await ask("/static/%2e%2e/files/x"))->Expect.toEqual((200, "x"))
  })

  testAsync("App.make refuses unsafe paths too", async t => {
    let reached = ref(false)
    let handler: Handler.t = async _ctx => {
      reached := true
      Respond.text("ok")
    }
    let app = handler->App.make
    t->expect((await app(TestSupport.request("/a%2Fb"))).status)->Expect.toBe(400)
    t->expect(reached.contents)->Expect.toBe(false)
    t->expect((await app(TestSupport.request("/a/b"))).status)->Expect.toBe(200)
  })

  testAsync("a HEAD request never gets a body, whatever answered it", async t => {
    let app =
      App.build()->App.router([
        Route.any(list{"any"}, async _ctx => Respond.text(~headers=dict{"x-a": "1"}, "a body")),
        Route.get(list{"throws"}, async _ctx => JsError.throwWithMessage("boom")),
      ])
    let head = async path => {
      let response = await app(TestSupport.request(~method="HEAD", path))
      (response.status, await response->Response.text)
    }
    t->expect(await head("/any"))->Expect.toEqual((200, ""))
    t->expect(await head("/nope"))->Expect.toEqual((404, ""))
    let app =
      App.build(~onError=(_error, _request) => Respond.text(~status=500, "failed"))->App.router([
        Route.get(list{"throws"}, async _ctx => JsError.throwWithMessage("boom")),
      ])
    let response = await app(TestSupport.request(~method="HEAD", "/throws"))
    t->expect((response.status, await response->Response.text))->Expect.toEqual((500, ""))
  })

  testAsync("map does something more with the finished application", async t => {
    let builder = App.build()->App.map(app => (app, "extra"))
    let (app, extra) =
      builder
      ->App.use(Middleware.responseHeaders(dict{"x-app": "yes"}))
      ->App.handle(async _ctx => Respond.text("ok"))
    let response = await app(TestSupport.request("/"))
    t->expect(extra)->Expect.toBe("extra")
    t->expect(response.headers->HttpHeaders.get("x-app"))->Expect.toEqual(Some("yes"))
  })

  testAsync("any handler will do: one that matches on the path itself", async t => {
    let handler: Handler.t = async ctx =>
      switch (ctx.method, ctx.path) {
      | (GET, list{"files", ...rest}) => Respond.text(rest->List.toArray->Array.join(" > "))
      | _ => Respond.notFound()
      }
    let app = handler->App.make
    let response = await app(TestSupport.request("/files/a/b/c"))
    t->expect(await response->Response.text)->Expect.toBe("a > b > c")
    t->expect((await app(TestSupport.request("/other"))).status)->Expect.toBe(404)
  })
})
