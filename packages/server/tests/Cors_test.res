open Vitest

let app: string = "https://app.example"

/**
Sends a request through `cors` to a handler that answers `ok`, recording whether
the handler ran.
*/
let send = async (~method: string="GET", ~headers: dict<string>=dict{}, cors: Middleware.t): (
  Response.t,
  bool,
) => {
  let reached = ref(false)
  let inner: Handler.t = async _ctx => {
    reached := true
    Respond.text("ok")->Respond.withHeader("Vary", "Accept-Encoding")
  }
  let handler = cors->Middleware.apply(inner)
  let response = await handler(TestSupport.context(~method, ~headers, "/data"))
  (response, reached.contents)
}

let header = (response: Response.t, name: string): option<string> =>
  response.headers->HttpHeaders.get(name)

let preflight = (
  ~requestHeaders: option<string>=?,
  ~origin: string=app,
  cors: Middleware.t,
): promise<(Response.t, bool)> => {
  let headers = dict{"Origin": origin, "Access-Control-Request-Method": "PUT"}
  requestHeaders->Option.forEach(value =>
    headers->Dict.set("Access-Control-Request-Headers", value)
  )
  send(~method="OPTIONS", ~headers, cors)
}

describe("Cors", () => {
  testAsync("Any allows every origin with a wildcard", async t => {
    let (response, reached) = await send(
      ~headers=dict{"Origin": app},
      Cors.middleware(~origins=Any),
    )
    t->expect(reached)->Expect.toBe(true)
    t->expect(await response->Response.text)->Expect.toBe("ok")
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(Some("*"))
    t->expect(response->header("access-control-allow-credentials"))->Expect.toEqual(None)
    // A wildcard answer doesn't depend on the origin.
    t->expect(response->header("vary"))->Expect.toEqual(Some("Accept-Encoding"))
  })

  testAsync("Any marks a response whether or not the request named an origin", async t => {
    // The same answer goes to everyone, so a cache that stores this one can
    // hand it to a request from another site.
    let (response, _) = await send(Cors.middleware(~origins=Any, ~exposeHeaders=["ETag"]))
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(Some("*"))
    t->expect(response->header("access-control-expose-headers"))->Expect.toEqual(Some("ETag"))
    t->expect(response->header("vary"))->Expect.toEqual(Some("Accept-Encoding"))
  })

  testAsync("Only allows the listed origins, naming the one that asked", async t => {
    let cors = Cors.middleware(~origins=Only([app, "https://admin.example"]))
    let (response, _) = await send(~headers=dict{"Origin": app}, cors)
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(Some(app))
    t->expect(response->header("vary"))->Expect.toEqual(Some("Accept-Encoding, Origin"))
  })

  testAsync("another origin still gets its answer, without permission to read it", async t => {
    let cors = Cors.middleware(~origins=Only([app]))
    let (response, reached) = await send(~headers=dict{"Origin": "https://evil.example"}, cors)
    t->expect(reached)->Expect.toBe(true)
    t->expect(response.status)->Expect.toBe(200)
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(None)
    t->expect(response->header("vary"))->Expect.toEqual(Some("Accept-Encoding, Origin"))
  })

  testAsync("origins are compared exactly", async t => {
    let cors = Cors.middleware(~origins=Only([app]))
    let allowed = async origin => {
      let (response, _) = await send(~headers=dict{"Origin": origin}, cors)
      response->header("access-control-allow-origin")->Option.isSome
    }
    t->expect(await allowed(app))->Expect.toBe(true)
    t->expect(await allowed("http://app.example"))->Expect.toBe(false)
    t->expect(await allowed("https://app.example.evil.test"))->Expect.toBe(false)
    t->expect(await allowed("https://sub.app.example"))->Expect.toBe(false)
    t->expect(await allowed("https://app.example:8443"))->Expect.toBe(false)
    t->expect(await allowed("null"))->Expect.toBe(false)
  })

  testAsync("Where asks a function", async t => {
    let cors = Cors.middleware(~origins=Where(origin => origin->String.endsWith(".example")))
    let (response, _) = await send(~headers=dict{"Origin": app}, cors)
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(Some(app))
    let (response, _) = await send(~headers=dict{"Origin": "https://other.test"}, cors)
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(None)
  })

  testAsync("a request with no Origin isn't a CORS request", async t => {
    let (response, reached) = await send(Cors.middleware(~origins=Only([app])))
    t->expect(reached)->Expect.toBe(true)
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(None)
    t->expect(response->header("vary"))->Expect.toEqual(Some("Accept-Encoding, Origin"))
  })

  testAsync("credentials and exposed headers", async t => {
    let cors = Cors.middleware(
      ~origins=Only([app]),
      ~credentials=true,
      ~exposeHeaders=["X-Total", "ETag"],
    )
    let (response, _) = await send(~headers=dict{"Origin": app}, cors)
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(Some(app))
    t->expect(response->header("access-control-allow-credentials"))->Expect.toEqual(Some("true"))
    t
    ->expect(response->header("access-control-expose-headers"))
    ->Expect.toEqual(Some("X-Total, ETag"))
  })

  test("credentials can't be combined with Any", t => {
    // Refused when the middleware is made, which is when the application is
    // set up, not when a request arrives.
    let threw = switch Cors.middleware(~origins=Any, ~credentials=true) {
    | _ => false
    | exception _ => true
    }
    t->expect(threw)->Expect.toBe(true)
  })

  test("credentials can't be combined with origins that let everyone in", t => {
    let throws = (origins: Cors.origins) =>
      switch Cors.middleware(~origins, ~credentials=true) {
      | _ => false
      | exception _ => true
      }
    t->expect(throws(Where(_ => true)))->Expect.toBe(true)
    t->expect(throws(Where(origin => origin->String.startsWith("https://"))))->Expect.toBe(true)
    t->expect(throws(Where(origin => origin == "null" || origin == app)))->Expect.toBe(true)
    t->expect(throws(Only([app, "null"])))->Expect.toBe(true)
    // A list, or a predicate that means something, is fine.
    t->expect(throws(Only([app])))->Expect.toBe(false)
    t->expect(throws(Where(origin => origin->String.endsWith(".app.example"))))->Expect.toBe(false)
    // And without credentials there's nothing to check.
    let open_ = switch Cors.middleware(~origins=Where(_ => true)) {
    | _ => "made"
    | exception _ => "refused"
    }
    t->expect(open_)->Expect.toBe("made")
  })

  testAsync("a preflight is answered without reaching the handler", async t => {
    let (response, reached) = await preflight(Cors.middleware(~origins=Only([app]), ~maxAge=600))
    t->expect(reached)->Expect.toBe(false)
    t->expect(response.status)->Expect.toBe(204)
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(Some(app))
    t
    ->expect(response->header("access-control-allow-methods"))
    ->Expect.toEqual(Some("GET, HEAD, POST, PUT, PATCH, DELETE"))
    t->expect(response->header("access-control-max-age"))->Expect.toEqual(Some("600"))
    t->expect(response->header("access-control-allow-headers"))->Expect.toEqual(None)
    t->expect(response->header("vary"))->Expect.toEqual(Some("Origin"))
  })

  testAsync("a preflight allows the headers asked for, or only the configured ones", async t => {
    let (response, _) = await preflight(
      ~requestHeaders="content-type, x-token",
      Cors.middleware(~origins=Any),
    )
    t
    ->expect(response->header("access-control-allow-headers"))
    ->Expect.toEqual(Some("content-type, x-token"))
    t->expect(response->header("vary"))->Expect.toEqual(Some("Access-Control-Request-Headers"))

    let (response, _) = await preflight(
      ~requestHeaders="content-type, x-token",
      Cors.middleware(~origins=Any, ~allowHeaders=["Content-Type"], ~methods=[GET, PUT]),
    )
    t
    ->expect(response->header("access-control-allow-headers"))
    ->Expect.toEqual(Some("Content-Type"))
    t->expect(response->header("access-control-allow-methods"))->Expect.toEqual(Some("GET, PUT"))
  })

  testAsync("a preflight from another origin gets no permission", async t => {
    let (response, reached) = await preflight(
      ~origin="https://evil.example",
      Cors.middleware(~origins=Only([app]), ~credentials=true),
    )
    t->expect(reached)->Expect.toBe(false)
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(None)
    t->expect(response->header("access-control-allow-methods"))->Expect.toEqual(None)
    t->expect(response->header("access-control-allow-credentials"))->Expect.toEqual(None)
  })

  testAsync("an OPTIONS request that isn't a preflight reaches the handler", async t => {
    let (_, reached) = await send(
      ~method="OPTIONS",
      ~headers=dict{"Origin": app},
      Cors.middleware(~origins=Any),
    )
    t->expect(reached)->Expect.toBe(true)
  })

  testAsync("works on a response whose headers are read-only", async t => {
    let redirect: Handler.t = async _ctx => Response.redirect(~url="http://example.test/next")
    let handler = Cors.middleware(~origins=Only([app]))->Middleware.apply(redirect)
    let response = await handler(TestSupport.context(~headers=dict{"Origin": app}, "/"))
    t->expect(response.status)->Expect.toBe(302)
    t->expect(response->header("access-control-allow-origin"))->Expect.toEqual(Some(app))
  })
})
