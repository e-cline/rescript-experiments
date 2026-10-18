open Vitest

describe("Cookie", () => {
  test("parse reads name=value pairs", t => {
    t->expect(Cookie.parse("a=1; b=2"))->Expect.toEqual(Map.fromArray([("a", "1"), ("b", "2")]))
    t
    ->expect(Cookie.parse("a=1;b=2 ;  c = 3 "))
    ->Expect.toEqual(Map.fromArray([("a", "1"), ("b", "2"), ("c", "3")]))
    t->expect(Cookie.parse(""))->Expect.toEqual(Map.make())
  })

  test("parse decodes values, and keeps ones it can't decode", t => {
    t->expect(Cookie.parse("q=a%20b%3Bc"))->Expect.toEqual(Map.fromArray([("q", "a b;c")]))
    t->expect(Cookie.parse("bad=100%"))->Expect.toEqual(Map.fromArray([("bad", "100%")]))
  })

  test("parse keeps `=` inside a value, strips quotes, and allows empty values", t => {
    t
    ->expect(Cookie.parse("token=abc==; quoted=\"hi there\"; empty="))
    ->Expect.toEqual(Map.fromArray([("token", "abc=="), ("quoted", "hi there"), ("empty", "")]))
  })

  test("parse skips pieces without a name, and keeps a repeated name's first value", t => {
    t
    ->expect(Cookie.parse("junk; =nameless; a=1; a=2"))
    ->Expect.toEqual(Map.fromArray([("a", "1")]))
  })

  test("parse keeps cookies whose names are also properties of every object", t => {
    let cookies = Cookie.parse("toString=a; constructor=b; __proto__=c; hasOwnProperty=d")
    t
    ->expect(cookies->Map.entries->Iterator.toArray)
    ->Expect.toEqual([
      ("toString", "a"),
      ("constructor", "b"),
      ("__proto__", "c"),
      ("hasOwnProperty", "d"),
    ])
  })

  test("a cookie that wasn't sent isn't found, whatever its name", t => {
    let cookies = Cookie.parse("a=1")
    t
    ->expect(
      ["toString", "constructor", "__proto__", "valueOf", "hasOwnProperty"]->Array.map(
        name => cookies->Map.get(name),
      ),
    )
    ->Expect.toEqual([None, None, None, None, None])
  })

  test("serialize uses cautious defaults", t => {
    t->expect(Cookie.serialize("id", "42"))->Expect.toBe("id=42; Path=/; HttpOnly; SameSite=Lax")
  })

  test("serialize writes every attribute", t => {
    t
    ->expect(
      Cookie.serialize(
        "id",
        "42",
        ~options={
          path: "/app",
          domain: "example.com",
          maxAge: 60,
          expires: Date.fromTime(86_400_000.0),
          httpOnly: false,
          secure: true,
          sameSite: Strict,
          partitioned: true,
        },
      ),
    )
    ->Expect.toBe(
      "id=42; Path=/app; Domain=example.com; Max-Age=60; Expires=Fri, 02 Jan 1970 00:00:00 GMT; Secure; SameSite=Strict; Partitioned",
    )
  })

  test("SameSite=None always comes with Secure", t => {
    t
    ->expect(Cookie.serialize("id", "42", ~options={sameSite: CrossSite, secure: false}))
    ->Expect.toBe("id=42; Path=/; HttpOnly; Secure; SameSite=None")
  })

  test("a value can be any string, and survives a round trip", t => {
    let value = "a b; c=d, \"quoted\" é\r\nSet-Cookie: evil=1"
    let header = Cookie.serialize("v", value)
    // Nothing in the value can end the cookie or start an attribute or a header.
    t
    ->expect(header)
    ->Expect.String.toMatch(/^v=[A-Za-z0-9%.\-_~!'()*]+; Path=\/; HttpOnly; SameSite=Lax$/)
    let pair = header->String.split(";")->Array.getUnsafe(0)
    t->expect(Cookie.parse(pair))->Expect.toEqual(Map.fromArray([("v", value)]))
  })

  test("serialize refuses names and attributes that could inject something", t => {
    let throws = f =>
      switch f() {
      | _ => false
      | exception _ => true
      }
    t->expect(throws(() => Cookie.serialize("a b", "x")))->Expect.toBe(true)
    t->expect(throws(() => Cookie.serialize("a=b", "x")))->Expect.toBe(true)
    t->expect(throws(() => Cookie.serialize("a;b", "x")))->Expect.toBe(true)
    t->expect(throws(() => Cookie.serialize("", "x")))->Expect.toBe(true)
    t
    ->expect(throws(() => Cookie.serialize("a", "x", ~options={path: "/; Domain=evil.test"})))
    ->Expect.toBe(true)
    t
    ->expect(throws(() => Cookie.serialize("a", "x", ~options={domain: "example.com\r\nX: y"})))
    ->Expect.toBe(true)
    t->expect(throws(() => Cookie.serialize("__Host-id.1", "x")))->Expect.toBe(false)
  })

  test("Secure is added wherever a browser requires it", t => {
    let has = (cookie: string, attribute: string) =>
      cookie->String.split("; ")->Array.includes(attribute)
    t->expect(Cookie.serialize("id", "1")->has("Secure"))->Expect.toBe(false)
    t->expect(Cookie.serialize("__Secure-id", "1")->has("Secure"))->Expect.toBe(true)
    t->expect(Cookie.serialize("__Host-id", "1")->has("Secure"))->Expect.toBe(true)
    t
    ->expect(
      Cookie.serialize("id", "1", ~options={partitioned: true, secure: false})->has("Secure"),
    )
    ->Expect.toBe(true)
    t->expect(Cookie.expire("__Host-id")->has("Secure"))->Expect.toBe(true)
    t->expect(Cookie.expire("id", ~secure=true)->has("Secure"))->Expect.toBe(true)
    t->expect(Cookie.expire("id", ~partitioned=true)->has("Partitioned"))->Expect.toBe(true)
    t->expect(Cookie.expire("id")->has("Secure"))->Expect.toBe(false)
  })

  test("a __Host- cookie can't have a domain or another path", t => {
    let throws = f =>
      switch f() {
      | _ => false
      | exception _ => true
      }
    t
    ->expect(throws(() => Cookie.serialize("__Host-id", "1", ~options={domain: "example.com"})))
    ->Expect.toBe(true)
    t
    ->expect(throws(() => Cookie.serialize("__Host-id", "1", ~options={path: "/app"})))
    ->Expect.toBe(true)
    t->expect(throws(() => Cookie.expire("__Host-id", ~path="/app")))->Expect.toBe(true)
    t
    ->expect(throws(() => Cookie.serialize("__Host-id", "1", ~options={path: "/"})))
    ->Expect.toBe(false)
    // The other prefix makes no such promise.
    t
    ->expect(throws(() => Cookie.serialize("__Secure-id", "1", ~options={domain: "example.com"})))
    ->Expect.toBe(false)
  })

  test("expire", t => {
    t
    ->expect(Cookie.expire("id", ~path="/app", ~domain="example.com"))
    ->Expect.toBe(
      "id=; Path=/app; Domain=example.com; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Lax",
    )
  })
})
