open Vitest

let text = (body: string): Handler.t => async _ctx => Respond.text(body)

let get = async (handler: Handler.t, path: string): (int, string) => {
  let response = await handler(TestSupport.context(path))
  (response.status, await response->Response.text)
}

describe("Router", () => {
  let router = Router.make([
    Route.get(list{}, text("home")),
    Route.get(list{"users", ":id"}, async ctx =>
      Respond.text(`user ${ctx->RequestContext.paramOrThrow("id")}`)
    ),
    Route.post(list{"users"}, text("created")),
    Route.none,
    Route.scope(
      list{"admin"},
      [next => async ctx => (await next(ctx))->Respond.withHeader("x-area", "admin")],
      [Route.get(list{"stats"}, text("stats"))],
    ),
    Route.get(list{"users", "me"}, text("shadowed by /users/:id")),
  ])

  testAsync("gives a request to the first route that matches", async t => {
    t->expect(await router->get("/"))->Expect.toEqual((200, "home"))
    t->expect(await router->get("/users/42"))->Expect.toEqual((200, "user 42"))
    t->expect(await router->get("/users/me"))->Expect.toEqual((200, "user me"))
    t->expect(await router->get("/admin/stats"))->Expect.toEqual((200, "stats"))
  })

  testAsync("answers 404 when no route has the path", async t => {
    t->expect(await router->get("/nope"))->Expect.toEqual((404, "Not Found"))
    t->expect(await router->get("/users/42/extra"))->Expect.toEqual((404, "Not Found"))
  })

  testAsync("answers 405 with Allow when a route has the path but not the method", async t => {
    let ask = async (~method: string, path: string) => {
      let response = await router(TestSupport.context(~method, path))
      (response.status, response.headers->HttpHeaders.get("allow"))
    }
    // /users takes POST only; /users/:id takes GET, and so HEAD.
    t->expect(await ask(~method="GET", "/users"))->Expect.toEqual((405, Some("POST, OPTIONS")))
    t->expect(await ask(~method="DELETE", "/users"))->Expect.toEqual((405, Some("POST, OPTIONS")))
    t
    ->expect(await ask(~method="POST", "/users/42"))
    ->Expect.toEqual((405, Some("GET, HEAD, OPTIONS")))
    t->expect(await ask(~method="POST", "/users"))->Expect.toEqual((200, None))
    t->expect(await ask(~method="POST", "/nope"))->Expect.toEqual((404, None))
  })

  testAsync("answers OPTIONS for a path with the methods it takes", async t => {
    let response = await router(TestSupport.context(~method="OPTIONS", "/users/42"))
    t->expect(response.status)->Expect.toBe(204)
    t
    ->expect(response.headers->HttpHeaders.get("allow"))
    ->Expect.toEqual(Some("GET, HEAD, OPTIONS"))
    t
    ->expect((await router(TestSupport.context(~method="OPTIONS", "/nope"))).status)
    ->Expect.toBe(404)
  })

  testAsync("lists every method a path takes, once", async t => {
    let ok: Handler.t = async _ctx => Respond.text("ok")
    let router = Router.make([
      Route.get(list{"things", ":id"}, ok),
      Route.delete(list{"things", ":id"}, ok),
      Route.put(list{"things", "special"}, ok),
      Route.get(list{"things", "special"}, ok),
      Route.method(Other("PURGE"), list{"things", ":id"}, ok),
    ])
    let response = await router(TestSupport.context(~method="POST", "/things/special"))
    t->expect(response.status)->Expect.toBe(405)
    t
    ->expect(response.headers->HttpHeaders.get("allow"))
    ->Expect.toEqual(Some("GET, HEAD, PUT, DELETE, PURGE, OPTIONS"))
  })

  testAsync("a GET route answers HEAD, without the body", async t => {
    let seen = ref(None)
    let router = Router.make([
      Route.get(
        list{"page"},
        async ctx => {
          seen := Some(ctx.method)
          Respond.html(~headers=dict{"x-page": "yes"}, Html.html`<h1>Page</h1>`)
        },
      ),
    ])
    let response = await router(TestSupport.context(~method="HEAD", "/page"))
    t->expect(response.status)->Expect.toBe(200)
    t->expect(response.headers->HttpHeaders.get("x-page"))->Expect.toEqual(Some("yes"))
    t->expect(response->TestSupport.contentType)->Expect.toEqual(Some("text/html; charset=utf-8"))
    t->expect(await response->Response.text)->Expect.toBe("")
    // The handler ran, and could tell.
    t->expect(seen.contents)->Expect.toEqual(Some(Method.HEAD))
    // Only GET routes: HEAD to a POST-only path is a method it doesn't take.
    t->expect((await router(TestSupport.context(~method="HEAD", "/nope"))).status)->Expect.toBe(404)
  })

  testAsync("a route for HEAD itself comes before a GET route's answer", async t => {
    let router = Router.make([
      Route.get(list{"page"}, async _ctx => Respond.text("from get")),
      Route.head(
        list{"page"},
        async _ctx => Respond.empty(~status=200, ~headers=dict{"x-from": "head"}),
      ),
    ])
    let response = await router(TestSupport.context(~method="HEAD", "/page"))
    t->expect(response.headers->HttpHeaders.get("x-from"))->Expect.toEqual(Some("head"))
  })

  testAsync(
    "a scope's middleware is around the answer to a method its routes don't take",
    async t => {
      let scoped = Router.make([
        Route.scope(
          list{"admin"},
          [next => async ctx => (await next(ctx))->Respond.withHeader("x-area", "admin")],
          [Route.post(list{"users"}, async _ctx => Respond.text("made"))],
        ),
      ])
      let response = await scoped(TestSupport.context("/admin/users"))
      t->expect(response.status)->Expect.toBe(405)
      t->expect(response.headers->HttpHeaders.get("x-area"))->Expect.toEqual(Some("admin"))
      // But not around a 404: no route there has that path.
      let response = await scoped(TestSupport.context("/admin/nope"))
      t->expect(response.headers->HttpHeaders.get("x-area"))->Expect.toEqual(None)
    },
  )

  testAsync("a GET route answers HEAD ahead of a later route for everything", async t => {
    let router = Router.make([
      Route.get(list{"page"}, async _ctx => Respond.text(~headers=dict{"x-from": "get"}, "page")),
      Route.any(list{"**"}, async _ctx => Respond.text(~status=404, "custom")),
    ])
    let response = await router(TestSupport.context(~method="HEAD", "/page"))
    t->expect(response.status)->Expect.toBe(200)
    t->expect(response.headers->HttpHeaders.get("x-from"))->Expect.toEqual(Some("get"))
    t->expect((await router(TestSupport.context(~method="HEAD", "/nope"))).status)->Expect.toBe(404)
  })

  testAsync("CORS on a scope answers the preflights for its routes", async t => {
    let scoped = Router.make([
      Route.scope(
        list{"api"},
        [Cors.middleware(~origins=Only(["https://app.example"]))],
        [Route.post(list{"items"}, async _ctx => Respond.text("made"))],
      ),
      Route.post(list{"other"}, async _ctx => Respond.text("other")),
    ])
    let preflight = path =>
      scoped(
        TestSupport.context(
          ~method="OPTIONS",
          ~headers=dict{
            "Origin": "https://app.example",
            "Access-Control-Request-Method": "POST",
          },
          path,
        ),
      )
    let response = await preflight("/api/items")
    t->expect(response.status)->Expect.toBe(204)
    t
    ->expect(response.headers->HttpHeaders.get("access-control-allow-origin"))
    ->Expect.toEqual(Some("https://app.example"))
    t
    ->expect(response.headers->HttpHeaders.get("access-control-allow-methods"))
    ->Expect.toEqual(Some("GET, HEAD, POST, PUT, PATCH, DELETE"))
    // A path outside the scope gets no permission.
    let response = await preflight("/other")
    t
    ->expect(response.headers->HttpHeaders.get("access-control-allow-origin"))
    ->Expect.toEqual(None)
  })

  testAsync("a route for everything takes requests before any of that applies", async t => {
    let router = Router.make([
      Route.post(list{"users"}, async _ctx => Respond.text("made")),
      Route.any(list{"**"}, async _ctx => Respond.text(~status=404, "custom")),
    ])
    t->expect(await router->get("/users"))->Expect.toEqual((404, "custom"))
  })

  testAsync("a scope's middleware apply to its routes only", async t => {
    let area = async path =>
      (await router(TestSupport.context(path))).headers->HttpHeaders.get("x-area")
    t->expect(await area("/admin/stats"))->Expect.toEqual(Some("admin"))
    t->expect(await area("/"))->Expect.toEqual(None)
    t->expect(await area("/admin/nope"))->Expect.toEqual(None)
  })

  testAsync("a last route matching everything replaces the 404", async t => {
    let router = Router.make([
      Route.get(list{"a"}, text("a")),
      Route.any(
        list{"**"},
        async ctx =>
          Respond.text(~status=404, `nothing at /${ctx.path->List.toArray->Array.join("/")}`),
      ),
    ])
    t->expect(await router->get("/a"))->Expect.toEqual((200, "a"))
    t->expect(await router->get("/b/c"))->Expect.toEqual((404, "nothing at /b/c"))
  })

  testAsync("an empty router answers 404 to everything", async t => {
    t->expect(await Router.make([])->get("/"))->Expect.toEqual((404, "Not Found"))
    t->expect(await Router.make([Route.none])->get("/a"))->Expect.toEqual((404, "Not Found"))
  })

  testAsync("a router is a handler: it nests under a `**` route", async t => {
    let api = Router.make([
      Route.get(list{"ping"}, async ctx => Respond.text(`pong from ${ctx.url.pathname}`)),
      Route.get(
        list{"items", ":item"},
        async ctx =>
          Respond.text(
            `${ctx->RequestContext.paramOrThrow("version")}: ${ctx->RequestContext.paramOrThrow(
                "item",
              )}`,
          ),
      ),
    ])
    let router = Router.make([
      Route.any(list{"api", ":version", "**"}, api),
      Route.get(list{"ping"}, text("top-level pong")),
    ])
    t->expect(await router->get("/api/v1/ping"))->Expect.toEqual((200, "pong from /api/v1/ping"))
    // The inner route sees the parameters the outer one bound, too.
    t->expect(await router->get("/api/v2/items/tea"))->Expect.toEqual((200, "v2: tea"))
    t->expect(await router->get("/api/v1/other"))->Expect.toEqual((404, "Not Found"))
    t->expect(await router->get("/ping"))->Expect.toEqual((200, "top-level pong"))
  })

  testAsync(
    "a nested router's answer is final; a scope's routes are tried with the rest",
    async t => {
      let inner = [Route.get(list{"ping"}, text("pong"))]
      let later = Route.get(list{"api", "status"}, text("status"))

      let nested = Router.make([Route.any(list{"api", "**"}, Router.make(inner)), later])
      t->expect(await nested->get("/api/ping"))->Expect.toEqual((200, "pong"))
      // The inner router took the request, and its 404 is the answer.
      t->expect(await nested->get("/api/status"))->Expect.toEqual((404, "Not Found"))

      let scoped = Router.make([Route.scope(list{"api"}, [], inner), later])
      t->expect(await scoped->get("/api/ping"))->Expect.toEqual((200, "pong"))
      t->expect(await scoped->get("/api/status"))->Expect.toEqual((200, "status"))
    },
  )

  testAsync("a nested router's parameter takes over a name the outer route bound", async t => {
    let show: Handler.t = async ctx =>
      Respond.text(
        `id=${ctx->RequestContext.paramOrThrow("id")} org=${ctx->RequestContext.paramOrThrow(
            "org",
          )}`,
      )
    let router = Router.make([
      Route.any(
        list{"orgs", ":org", "users", ":id", "**"},
        Router.make([Route.get(list{"posts", ":id"}, show), Route.get(list{}, show)]),
      ),
    ])
    // Its own `:id` for its handlers; the outer one where it has none.
    t
    ->expect(await router->get("/orgs/acme/users/1/posts/2"))
    ->Expect.toEqual((200, "id=2 org=acme"))
    t->expect(await router->get("/orgs/acme/users/1"))->Expect.toEqual((200, "id=1 org=acme"))
  })

  testAsync("a router is a handler: middleware wrap it like any other", async t => {
    let seen = []
    let handler = Middleware.logger(~log=line => seen->Array.push(line))->Middleware.apply(router)
    let _ = await handler->get("/users/42")
    let _ = await handler->get("/nope")
    t
    ->expect(seen->Array.map(line => line->String.split(" ")->Array.slice(~start=0, ~end=3)))
    ->Expect.toEqual([["GET", "/users/42", "200"], ["GET", "/nope", "404"]])
  })

  testAsync("a handler behind a `**` route can match on the rest of the path itself", async t => {
    let files: Handler.t = async ctx =>
      switch ctx.path {
      | list{} => Respond.text("index")
      | list{dir, file} => Respond.text(`${file} in ${dir}`)
      | _ => Respond.notFound()
      }
    let router = Router.make([Route.get(list{"files", "**"}, files)])
    t->expect(await router->get("/files"))->Expect.toEqual((200, "index"))
    t->expect(await router->get("/files/docs/a.txt"))->Expect.toEqual((200, "a.txt in docs"))
    t->expect(await router->get("/files/a/b/c"))->Expect.toEqual((404, "Not Found"))
  })
})
