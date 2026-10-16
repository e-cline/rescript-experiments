open Vitest

let nameKey: Context.Key.t<string> = Context.Key.make(~name="name")
let countKey: Context.Key.t<int> = Context.Key.make(~name="count")

describe("RequestContext", () => {
  test("path is the URL path's decoded segments", t => {
    let path = url => TestSupport.context(url).path
    t->expect(path("/"))->Expect.toEqual(list{})
    t->expect(path("/users"))->Expect.toEqual(list{"users"})
    t->expect(path("/users/42/posts"))->Expect.toEqual(list{"users", "42", "posts"})
    t->expect(path("/users/42/?x=1#top"))->Expect.toEqual(list{"users", "42"})
    t->expect(path("//users//42"))->Expect.toEqual(list{"users", "42"})
    t->expect(path("/files/a%20b/caf%C3%A9"))->Expect.toEqual(list{"files", "a b", "café"})
  })

  // Parsing keeps it in one segment rather than splitting on it; `isPathSafe`
  // is what then says no handler should be given it.
  test("an encoded slash stays inside its segment", t => {
    t->expect(TestSupport.context("/files/a%2Fb").path)->Expect.toEqual(list{"files", "a/b"})
  })

  test("a segment that isn't valid percent-encoding is kept as it is", t => {
    t
    ->expect(RequestContext.pathSegments("/a/%E0%A4%A/b"))
    ->Expect.toEqual(list{"a", "%E0%A4%A", "b"})
  })

  test("method", t => {
    t->expect(TestSupport.context("/").method)->Expect.toEqual(Method.GET)
    t->expect(TestSupport.context(~method="DELETE", "/").method)->Expect.toEqual(Method.DELETE)
    t
    ->expect(TestSupport.context(~method="PROPFIND", "/").method)
    ->Expect.toEqual(Method.Other("PROPFIND"))
    t->expect(Method.fromString("post"))->Expect.toEqual(Method.POST)
    t->expect(Method.Other("PROPFIND")->Method.toString)->Expect.toBe("PROPFIND")
  })

  test("query and header", t => {
    let ctx = TestSupport.context(~headers=dict{"X-Token": "abc"}, "/search?q=rescript&page=2")
    t->expect(ctx.query->Query.get("q"))->Expect.toEqual(Some("rescript"))
    t->expect(ctx.query->Query.getInt("page"))->Expect.toEqual(Some(2))
    t->expect(ctx->RequestContext.header("x-token"))->Expect.toEqual(Some("abc"))
    t->expect(ctx->RequestContext.header("X-TOKEN"))->Expect.toEqual(Some("abc"))
    t->expect(ctx->RequestContext.header("missing"))->Expect.toEqual(None)
  })

  test("cookie and cookies", t => {
    let ctx = TestSupport.context(~headers=dict{"Cookie": "session=abc123; theme=dark%20mode"}, "/")
    t->expect(ctx->RequestContext.cookie("session"))->Expect.toEqual(Some("abc123"))
    t->expect(ctx->RequestContext.cookie("theme"))->Expect.toEqual(Some("dark mode"))
    t->expect(ctx->RequestContext.cookie("missing"))->Expect.toEqual(None)
    t
    ->expect(ctx->RequestContext.cookies)
    ->Expect.toEqual(Map.fromArray([("session", "abc123"), ("theme", "dark mode")]))
    t->expect(TestSupport.context("/")->RequestContext.cookies)->Expect.toEqual(Map.make())
    t->expect(TestSupport.context("/")->RequestContext.cookie("session"))->Expect.toEqual(None)
  })

  test("param and paramOrThrow read the parameters a route bound", t => {
    let ctx = {...TestSupport.context("/"), params: Map.fromArray([("id", "42")])}
    t->expect(ctx->RequestContext.param("id"))->Expect.toEqual(Some("42"))
    t->expect(ctx->RequestContext.param("other"))->Expect.toEqual(None)
    t->expect(ctx->RequestContext.paramOrThrow("id"))->Expect.toBe("42")
    let message = switch ctx->RequestContext.paramOrThrow("other") {
    | _ => "didn't throw"
    | exception JsExn(error) => error->JsExn.message->Option.getOr("")
    }
    t->expect(message)->Expect.String.toContain(`":other"`)
    t->expect(TestSupport.context("/users/42").params)->Expect.toEqual(Map.make())
  })

  test("a cookie or parameter that isn't there isn't found, whatever its name", t => {
    let ctx = TestSupport.context(~headers=dict{"Cookie": "a=1"}, "/")
    let names = ["toString", "constructor", "__proto__", "valueOf"]
    t
    ->expect(names->Array.map(name => ctx->RequestContext.cookie(name)))
    ->Expect.toEqual([None, None, None, None])
    t
    ->expect(names->Array.map(name => ctx->RequestContext.param(name)))
    ->Expect.toEqual([None, None, None, None])

    let sent = TestSupport.context(~headers=dict{"Cookie": "constructor=yes"}, "/")
    t->expect(sent->RequestContext.cookie("constructor"))->Expect.toEqual(Some("yes"))
  })

  test("request headers as a map", t => {
    let ctx = TestSupport.context(~headers=dict{"X-Token": "abc"}, "/")
    let headers = ctx.request.headers->HttpHeaders.toMap
    t->expect(headers->Map.get("x-token"))->Expect.toEqual(Some("abc"))
    t->expect(headers->Map.get("constructor"))->Expect.toEqual(None)
    t->expect(headers->Map.get("toString"))->Expect.toEqual(None)
  })

  test("isSegmentSafe refuses what can't be one name in a path", t => {
    let safe = RequestContext.isSegmentSafe
    let fine = ["users", "a b", "café", "report.pdf", "..hidden", "a..b", "%41", ":id", "~"]
    t->expect(fine->Array.filter(segment => !safe(segment)))->Expect.toEqual([])
    let unsafe = [".", "..", "a/b", "../x", "a\\b", "a\u0000b", "a\nb", "\t", "a\u007Fb"]
    t->expect(unsafe->Array.filter(safe))->Expect.toEqual([])
  })

  test("isPathSafe looks at the whole path, decoded", t => {
    let safe = path => TestSupport.context(path)->RequestContext.isPathSafe
    t->expect(safe("/"))->Expect.toBe(true)
    t->expect(safe("/users/42/report.pdf?x=../y"))->Expect.toBe(true)
    t->expect(safe("/files/a%20b/caf%C3%A9"))->Expect.toBe(true)
    // Dot segments written out are resolved by the URL parser before we see them.
    t->expect(safe("/a/../b"))->Expect.toBe(true)
    t->expect(safe("/a/%2e%2e/b"))->Expect.toBe(true)
    // It's the encoded ones, which survive that, that are refused.
    t->expect(safe("/static/..%2F..%2Fetc%2Fpasswd"))->Expect.toBe(false)
    t->expect(safe("/static/..%5C..%5Cwin"))->Expect.toBe(false)
    t->expect(safe("/static/a%2Fb"))->Expect.toBe(false)
    t->expect(safe("/static/a%00b"))->Expect.toBe(false)
    t->expect(safe("/static/a%0Ab"))->Expect.toBe(false)
    // Wherever in the path it is, and whatever part has been routed already.
    t->expect(safe("/a%2Fb/c/d"))->Expect.toBe(false)
    let routed = TestSupport.context("/a%2Fb/c")->RequestContext.withPath(list{"c"})
    t->expect(routed->RequestContext.isPathSafe)->Expect.toBe(false)
  })

  test("withPath changes only the path", t => {
    let ctx = TestSupport.context("/api/users?x=1")
    let nested = ctx->RequestContext.withPath(list{"users"})
    t->expect(nested.path)->Expect.toEqual(list{"users"})
    t->expect(nested.url.pathname)->Expect.toBe("/api/users")
    t->expect(nested.query->Query.get("x"))->Expect.toEqual(Some("1"))
    t->expect(ctx.path)->Expect.toEqual(list{"api", "users"})
  })

  test("get and set attach typed values to a context", t => {
    let ctx = TestSupport.context("/")
    t->expect(ctx->RequestContext.get(nameKey))->Expect.toEqual(None)

    let withName = ctx->RequestContext.set(nameKey, "Ada")
    let withBoth = withName->RequestContext.set(countKey, 3)
    t->expect(withBoth->RequestContext.get(nameKey))->Expect.toEqual(Some("Ada"))
    t->expect(withBoth->RequestContext.get(countKey))->Expect.toEqual(Some(3))
    // Each `set` made a new context and left the one it started from alone.
    t->expect(withName->RequestContext.get(countKey))->Expect.toEqual(None)
    t->expect(ctx->RequestContext.get(nameKey))->Expect.toEqual(None)
  })

  test("values survive withPath, and set keeps the rest of the context", t => {
    let ctx = TestSupport.context("/api/users?x=1")->RequestContext.set(nameKey, "Ada")
    t->expect(ctx.path)->Expect.toEqual(list{"api", "users"})
    t->expect(ctx.query->Query.get("x"))->Expect.toEqual(Some("1"))
    t
    ->expect(ctx->RequestContext.withPath(list{"users"})->RequestContext.get(nameKey))
    ->Expect.toEqual(Some("Ada"))
  })

  test("getOrThrow returns the value, or throws naming the key", t => {
    let ctx = TestSupport.context("/")
    t
    ->expect(ctx->RequestContext.set(countKey, 3)->RequestContext.getOrThrow(countKey))
    ->Expect.toBe(3)
    let message = switch ctx->RequestContext.getOrThrow(countKey) {
    | _ => "didn't throw"
    | exception JsExn(error) => error->JsExn.message->Option.getOr("")
    }
    t->expect(message)->Expect.String.toContain(`"count"`)
  })

  testAsync("text reads the body", async t => {
    let ctx = TestSupport.context(~method="POST", ~body="hello", "/")
    t->expect(await ctx->RequestContext.text)->Expect.toBe("hello")
    t->expect(await TestSupport.context("/")->RequestContext.text)->Expect.toBe("")
  })

  test("contentType is the media type, without parameters, in lower case", t => {
    let of_ = value =>
      TestSupport.context(~headers=dict{"Content-Type": value}, "/")->RequestContext.contentType
    t->expect(of_("application/json"))->Expect.toEqual(Some("application/json"))
    t->expect(of_("Application/JSON; charset=utf-8"))->Expect.toEqual(Some("application/json"))
    t->expect(of_("text/html ;charset=utf-8"))->Expect.toEqual(Some("text/html"))
    t->expect(TestSupport.context("/")->RequestContext.contentType)->Expect.toEqual(None)
  })

  testAsync("json parses a body that says it is JSON", async t => {
    let post = (~contentType, body) =>
      TestSupport.context(~method="POST", ~headers=dict{"content-type": contentType}, ~body, "/")
    let value = JSON.parseOrThrow(`{"a":[1,2]}`)
    t
    ->expect(await post(~contentType="application/json", `{"a":[1,2]}`)->RequestContext.json)
    ->Expect.toEqual(Ok(value))
    t
    ->expect(
      await post(
        ~contentType="Application/JSON; charset=utf-8",
        `{"a":[1,2]}`,
      )->RequestContext.json,
    )
    ->Expect.toEqual(Ok(value))
    t
    ->expect(
      await post(~contentType="application/problem+json", `{"a":[1,2]}`)->RequestContext.json,
    )
    ->Expect.toEqual(Ok(value))
  })

  testAsync("json refuses a body that doesn't say it is JSON", async t => {
    // What a page on another site can make a browser send without asking.
    let post = (~headers=dict{}, body) => TestSupport.context(~method="POST", ~headers, ~body, "/")
    let body = `{"a":1}`
    let wrong = actual => Error(
      RequestContext.WrongContentType({expected: "application/json", actual}),
    )
    t
    ->expect(await post(~headers=dict{"content-type": "text/plain"}, body)->RequestContext.json)
    ->Expect.toEqual(wrong(Some("text/plain")))
    t
    ->expect(
      await post(
        ~headers=dict{"content-type": "application/x-www-form-urlencoded"},
        body,
      )->RequestContext.json,
    )
    ->Expect.toEqual(wrong(Some("application/x-www-form-urlencoded")))
    // A string body with no header is sent as text/plain.
    t->expect(await post(body)->RequestContext.json)->Expect.toEqual(wrong(Some("text/plain")))
    t
    ->expect(await TestSupport.context(~method="POST", "/")->RequestContext.json)
    ->Expect.toEqual(wrong(None))

    // Unless asked to take it anyway.
    t
    ->expect(await post(body)->RequestContext.json(~anyContentType=true))
    ->Expect.toEqual(Ok(JSON.parseOrThrow(body)))
  })

  testAsync("json reports invalid JSON as Malformed", async t => {
    let post = body =>
      TestSupport.context(
        ~method="POST",
        ~headers=dict{"content-type": "application/json"},
        ~body,
        "/",
      )
    let isMalformed = result =>
      switch result {
      | Error(RequestContext.Malformed(_)) => true
      | _ => false
      }
    t->expect(isMalformed(await post("{nope")->RequestContext.json))->Expect.toBe(true)
    t->expect(isMalformed(await post("")->RequestContext.json))->Expect.toBe(true)
  })

  testAsync("form reads a URL-encoded body, and refuses any other kind", async t => {
    let post = (~contentType, body) =>
      TestSupport.context(~method="POST", ~headers=dict{"content-type": contentType}, ~body, "/")
    switch await post(
      ~contentType="application/x-www-form-urlencoded",
      "name=Ada+Lovelace&age=36",
    )->RequestContext.form {
    | Ok(form) =>
      t->expect(form->Query.get("name"))->Expect.toEqual(Some("Ada Lovelace"))
      t->expect(form->Query.getInt("age"))->Expect.toEqual(Some(36))
    | Error(error) => t->expect(RequestContext.bodyErrorMessage(error))->Expect.toBe("a form")
    }
    let multipart = await post(
      ~contentType="multipart/form-data; boundary=x",
      "--x--",
    )->RequestContext.form
    t
    ->expect(
      switch multipart {
      | Error(WrongContentType({actual})) => actual
      | _ => None
      },
    )
    ->Expect.toEqual(Some("multipart/form-data"))
  })

  test("bodyErrorMessage", t => {
    let message = RequestContext.bodyErrorMessage
    t
    ->expect(message(WrongContentType({expected: "application/json", actual: Some("text/plain")})))
    ->Expect.toBe("Expected a body of type application/json, not text/plain")
    t
    ->expect(message(WrongContentType({expected: "application/json", actual: None})))
    ->Expect.String.toContain("Content-Type")
    t->expect(message(Malformed("Unexpected token")))->Expect.toBe("Unexpected token")
  })

  test("bearerToken reads an Authorization header, whatever the scheme's case", t => {
    let token = value =>
      TestSupport.context(~headers=dict{"Authorization": value}, "/")->RequestContext.bearerToken
    t->expect(token("Bearer abc.def"))->Expect.toEqual(Some("abc.def"))
    t->expect(token("bearer abc"))->Expect.toEqual(Some("abc"))
    t->expect(token("BEARER   abc  "))->Expect.toEqual(Some("abc"))
    t->expect(token("Basic dXNlcjpwYXNz"))->Expect.toEqual(None)
    t->expect(token("Bearer"))->Expect.toEqual(None)
    t->expect(token("Bearer "))->Expect.toEqual(None)
    t->expect(token("abc"))->Expect.toEqual(None)
    t->expect(TestSupport.context("/")->RequestContext.bearerToken)->Expect.toEqual(None)
  })

  testAsync("reading a body twice is thrown, not reported as invalid JSON", async t => {
    let ctx = TestSupport.context(
      ~method="POST",
      ~headers=dict{"content-type": "application/json"},
      ~body=`{"a":1}`,
      "/",
    )
    t->expect((await ctx->RequestContext.json)->Result.isOk)->Expect.toBe(true)
    let second = switch await ctx->RequestContext.json {
    | Ok(_) => "ok"
    | Error(error) => `reported as an error: ${RequestContext.bodyErrorMessage(error)}`
    | exception _ => "thrown"
    }
    t->expect(second)->Expect.toBe("thrown")
  })
})
