open Vitest

/** A middleware that records when it runs, before and after the handler it wraps. */
let tracing = (log: array<string>, name: string): Middleware.t =>
  next =>
    async ctx => {
      log->Array.push(`${name} before`)
      let response = await next(ctx)
      log->Array.push(`${name} after`)
      response
    }

let ok: Handler.t = async _ctx => Respond.text("ok")

let text = async (handler: Handler.t): string =>
  await (await handler(TestSupport.context("/")))->Response.text

/** The text of `handler` wrapped in `middleware`. */
let through = (middleware: Middleware.t, handler: Handler.t): promise<string> =>
  text(middleware->Middleware.apply(handler))

let userKey: Context.Key.t<string> = Context.Key.make(~name="user")
let counterKey: Context.Key.t<ref<int>> = Context.Key.make(~name="counter")

describe("Middleware", () => {
  testAsync("apply wraps a handler in a middleware", async t => {
    let log = []
    let handler: Handler.t = async _ctx => {
      log->Array.push("handler")
      Respond.text("ok")
    }
    t->expect(await tracing(log, "outer")->through(handler))->Expect.toBe("ok")
    t->expect(log)->Expect.toEqual(["outer before", "handler", "outer after"])
  })

  testAsync("pipeline puts the first middleware outermost", async t => {
    let log = []
    let middleware = Middleware.pipeline([tracing(log, "a"), tracing(log, "b"), tracing(log, "c")])
    let _ = await middleware->through(ok)
    t
    ->expect(log)
    ->Expect.toEqual(["a before", "b before", "c before", "c after", "b after", "a after"])
  })

  testAsync("pipeline is the same as applying each in turn", async t => {
    let viaPipeline = []
    let _ = await Middleware.pipeline([
      tracing(viaPipeline, "a"),
      tracing(viaPipeline, "b"),
    ])->through(ok)
    let byHand = []
    let _ = await tracing(byHand, "a")->through(tracing(byHand, "b")->Middleware.apply(ok))
    t->expect(viaPipeline)->Expect.toEqual(byHand)
    t->expect(byHand)->Expect.toEqual(["a before", "b before", "b after", "a after"])
  })

  testAsync("none is the identity, alone and in a pipeline", async t => {
    t->expect(Middleware.none->Middleware.apply(ok))->Expect.toBe(ok)
    t->expect(Middleware.pipeline([])->Middleware.apply(ok))->Expect.toBe(ok)

    let log = []
    let middleware = Middleware.pipeline([Middleware.none, tracing(log, "a"), Middleware.none])
    let _ = await middleware->through(ok)
    t->expect(log)->Expect.toEqual(["a before", "a after"])
  })

  testAsync("pipelines nest: grouping doesn't matter", async t => {
    let run = async (build: array<string> => Middleware.t): array<string> => {
      let log = []
      let _ = await build(log)->through(ok)
      log
    }
    let flat = await run(
      log => Middleware.pipeline([tracing(log, "a"), tracing(log, "b"), tracing(log, "c")]),
    )
    let left = await run(
      log =>
        Middleware.pipeline([
          Middleware.pipeline([tracing(log, "a"), tracing(log, "b")]),
          tracing(log, "c"),
        ]),
    )
    let right = await run(
      log =>
        Middleware.pipeline([
          tracing(log, "a"),
          Middleware.pipeline([tracing(log, "b"), tracing(log, "c")]),
        ]),
    )
    t->expect(left)->Expect.toEqual(flat)
    t->expect(right)->Expect.toEqual(flat)
  })

  testAsync("a middleware can answer without calling the handler", async t => {
    let called = ref(false)
    let deny: Middleware.t = _next => async _ctx => Respond.text(~status=403, "no")
    let handler: Handler.t = async _ctx => {
      called := true
      Respond.text("ok")
    }
    let response = await (deny->Middleware.apply(handler))(TestSupport.context("/"))
    t->expect(response.status)->Expect.toBe(403)
    t->expect(called.contents)->Expect.toBe(false)
  })

  testAsync("a middleware can attach a value for the handlers behind it", async t => {
    // A `Map`, not a `dict`: the token comes from the client, and looking up
    // `"constructor"` in a `dict` finds something.
    let tokens = Map.fromArray([("secret", "Ada")])
    let authenticate: Middleware.t = next =>
      async ctx =>
        switch ctx
        ->RequestContext.header("authorization")
        ->Option.flatMap(token => tokens->Map.get(token)) {
        | Some(user) => await next(ctx->RequestContext.set(userKey, user))
        | None => Respond.text(~status=401, "Unauthorized")
        }
    let greet: Handler.t = async ctx =>
      Respond.text(`Hello, ${ctx->RequestContext.getOrThrow(userKey)}`)
    let handler = authenticate->Middleware.apply(greet)

    let response = await handler(TestSupport.context(~headers=dict{"Authorization": "secret"}, "/"))
    t->expect(await response->Response.text)->Expect.toBe("Hello, Ada")

    let response = await handler(TestSupport.context("/"))
    t->expect(response.status)->Expect.toBe(401)

    let response = await handler(
      TestSupport.context(~headers=dict{"Authorization": "constructor"}, "/"),
    )
    t->expect(response.status)->Expect.toBe(401)
  })

  testAsync("provide attaches the same value to every request", async t => {
    let counter = ref(0)
    let count: Handler.t = async ctx => {
      let counter = ctx->RequestContext.getOrThrow(counterKey)
      counter := counter.contents + 1
      Respond.text(counter.contents->Int.toString)
    }
    let handler = Middleware.provide(counterKey, counter)->Middleware.apply(count)
    let _ = await text(handler)
    t->expect(await text(handler))->Expect.toBe("2")
    t->expect(counter.contents)->Expect.toBe(2)
  })

  testAsync("middleware attaching different keys compose in either order", async t => {
    let handler: Handler.t = async ctx => {
      let user = ctx->RequestContext.getOrThrow(userKey)
      let counter = ctx->RequestContext.getOrThrow(counterKey)
      Respond.text(`${user} ${counter.contents->Int.toString}`)
    }
    let user = Middleware.provide(userKey, "Ada")
    let counter = Middleware.provide(counterKey, ref(7))
    t->expect(await Middleware.pipeline([user, counter])->through(handler))->Expect.toBe("Ada 7")
    t->expect(await Middleware.pipeline([counter, user])->through(handler))->Expect.toBe("Ada 7")
  })

  testAsync(
    "an inner middleware's value replaces an outer one's, for what's behind it",
    async t => {
      let seenByOuter = ref(None)
      let outer: Middleware.t = next =>
        async ctx => {
          let ctx = ctx->RequestContext.set(userKey, "outer")
          let response = await next(ctx)
          // What the outer middleware holds is unchanged by what happened inside.
          seenByOuter := ctx->RequestContext.get(userKey)
          response
        }
      let handler: Handler.t = async ctx => Respond.text(ctx->RequestContext.getOrThrow(userKey))
      let middleware = Middleware.pipeline([outer, Middleware.provide(userKey, "inner")])
      t->expect(await middleware->through(handler))->Expect.toBe("inner")
      t->expect(seenByOuter.contents)->Expect.toEqual(Some("outer"))
    },
  )

  testAsync("responseHeaders adds headers the response doesn't already have", async t => {
    let handler: Handler.t = async _ctx =>
      Respond.text(~headers=dict{"Cache-Control": "max-age=60"}, "ok")
    let headers = Middleware.responseHeaders(
      dict{
        "X-Frame-Options": "DENY",
        "Cache-Control": "no-store",
      },
    )
    let response = await (headers->Middleware.apply(handler))(TestSupport.context("/"))
    t->expect(response.headers->HttpHeaders.get("x-frame-options"))->Expect.toEqual(Some("DENY"))
    t
    ->expect(response.headers->HttpHeaders.get("cache-control"))
    ->Expect.toEqual(Some("max-age=60"))
  })

  testAsync("logger logs the method, path, query and status", async t => {
    let lines = []
    let handler: Handler.t = async _ctx => Respond.text(~status=201, "made")
    let logged = Middleware.logger(~log=line => lines->Array.push(line))->Middleware.apply(handler)
    let _ = await logged(TestSupport.context(~method="POST", "/things?x=1"))
    t->expect(lines->Array.length)->Expect.toBe(1)
    t->expect(lines->Array.getUnsafe(0))->Expect.String.toMatch(/^POST \/things\?x=1 201 \d+ms$/)
  })

  testAsync("recover answers for a handler that throws or rejects", async t => {
    let recover = Middleware.recover(
      async (_error, ctx) => Respond.text(~status=500, `failed on ${ctx.url.pathname}`),
    )
    let throws: Handler.t = async _ctx => JsError.throwWithMessage("boom")
    let response = await (recover->Middleware.apply(throws))(TestSupport.context("/a"))
    t->expect(response.status)->Expect.toBe(500)
    t->expect(await response->Response.text)->Expect.toBe("failed on /a")

    let rejects: Handler.t = _ctx => Promise.reject(Failure("boom"))
    let response = await (recover->Middleware.apply(rejects))(TestSupport.context("/b"))
    t->expect(await response->Response.text)->Expect.toBe("failed on /b")
  })

  testAsync("the included middleware are all Middleware.t values", async t => {
    let lines = []
    let middleware: array<Middleware.t> = [
      Middleware.logger(~log=line => lines->Array.push(line)),
      Middleware.logger(),
      Middleware.provide(userKey, "Ada"),
      Middleware.responseHeaders(dict{"X-A": "1"}),
      Middleware.recover(async (_error, _ctx) => Respond.text(~status=500, "failed")),
      Cors.middleware(~origins=Any),
    ]
    let handler: Handler.t = async ctx => Respond.text(ctx->RequestContext.getOrThrow(userKey))
    let response = await (Middleware.pipeline(middleware)->Middleware.apply(handler))(
      TestSupport.context("/"),
    )
    t->expect(await response->Response.text)->Expect.toBe("Ada")
    t->expect(response.headers->HttpHeaders.get("x-a"))->Expect.toEqual(Some("1"))
    t->expect(lines->Array.length)->Expect.toBe(1)
  })
})
