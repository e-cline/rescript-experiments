/***
Tests of the example server's routes. No server is started: the application
is a function from `Request` to `Response`, so each test just calls it.
*/

open Vitest

/** Sends a request to `app`, or to a fresh application if none is given. */
let send = (~app=Routes.make(), ~method="GET", ~headers=dict{}, ~body=?, path) =>
  app(
    Request.fromURL(
      `http://localhost${path}`,
      ~init={
        method,
        headers: HeadersInit.fromDict(headers),
        body: ?(body->Option.map(BodyInit.fromString)),
      },
    ),
  )

let contentType = (response: Response.t) =>
  response.headers->ResServer.HttpHeaders.get("content-type")

/** Reads a JSON object body, returning a lookup of its fields. */
let json = async (response: Response.t) => {
  let fields = (await response->Response.json)->JSON.Decode.object->Option.getOr(dict{})
  key => fields->Dict.get(key)
}

describe("Routes", () => {
  testAsync("GET / sends HTML", async t => {
    let response = await send("/")
    t->expect(response.status)->Expect.toBe(200)
    t->expect(response->contentType)->Expect.toBe(Some("text/html; charset=utf-8"))
    t->expect(await response->Response.text)->Expect.String.toContain("<code>/hello/:name</code>")
  })

  testAsync("GET /hello sends text, using the query string", async t => {
    let response = await send("/hello")
    t->expect(response->contentType)->Expect.toBe(Some("text/plain; charset=utf-8"))
    t->expect(await response->Response.text)->Expect.toBe("Hello, world!\n")

    let response = await send("/hello?name=Ada")
    t->expect(await response->Response.text)->Expect.toBe("Hello, Ada!\n")
  })

  testAsync("GET /hello/:name uses the path segment", async t => {
    let response = await send("/hello/Grace%20Hopper")
    t->expect(await response->Response.text)->Expect.toBe("Hello, Grace Hopper!\n")
  })

  testAsync("GET /time sends JSON", async t => {
    let response = await send("/time")
    t->expect(response->contentType)->Expect.toBe(Some("application/json"))
    let field = await response->json
    t->expect(field("iso")->Option.flatMap(JSON.Decode.string)->Option.isSome)->Expect.toBe(true)
    t->expect(field("epochMs")->Option.flatMap(JSON.Decode.float)->Option.isSome)->Expect.toBe(true)
  })

  testAsync("POST /echo sends the body back with its content type", async t => {
    let body = `{"greeting":"hi"}`
    let response = await send(
      "/echo",
      ~method="POST",
      ~headers=dict{"content-type": "application/json"},
      ~body,
    )
    t->expect(response.status)->Expect.toBe(200)
    t->expect(response->contentType)->Expect.toBe(Some("application/json"))
    t->expect(await response->Response.text)->Expect.toBe(body)
  })

  testAsync("/inspect describes the request", async t => {
    let response = await send(
      "/inspect?a=1&b=two",
      ~method="PUT",
      ~headers=dict{"x-example": "yes"},
      ~body="payload",
    )
    let field = await response->json
    t->expect(field("method"))->Expect.toEqual(Some(JSON.Encode.string("PUT")))
    t->expect(field("path"))->Expect.toEqual(Some(JSON.Encode.string("/inspect")))
    t->expect(field("segments"))->Expect.toEqual(Some(JSON.parseOrThrow(`["inspect"]`)))
    t->expect(field("query"))->Expect.toEqual(Some(JSON.parseOrThrow(`{"a":"1","b":"two"}`)))
    t
    ->expect(
      field("headers")
      ->Option.flatMap(JSON.Decode.object)
      ->Option.flatMap(Dict.get(_, "x-example")),
    )
    ->Expect.toEqual(Some(JSON.Encode.string("yes")))
    t->expect(field("body"))->Expect.toEqual(Some(JSON.Encode.string("payload")))
  })

  testAsync("/inspect reports query parameters whatever they're called", async t => {
    let response = await send("/inspect?toString=1&constructor=2&a=3")
    let field = await response->json
    t
    ->expect(field("query"))
    ->Expect.toEqual(Some(JSON.parseOrThrow(`{"toString":"1","constructor":"2","a":"3"}`)))
  })

  testAsync("GET /events streams NDJSON, one line per chunk", async t => {
    let response = await send("/events?count=3&intervalMs=1")
    t->expect(response->contentType)->Expect.toBe(Some("application/x-ndjson; charset=utf-8"))
    let chunks = switch response.body->Null.toOption {
    | Some(body) => await body->ResServer.ByteStream.fromBody->ResServer.ByteStream.toTextChunks
    | None => []
    }
    t
    ->expect(
      chunks->Array.map(
        line => JSON.parseOrThrow(line)->JSON.Decode.object->Option.flatMap(Dict.get(_, "index")),
      ),
    )
    ->Expect.toEqual([0, 1, 2]->Array.map(index => Some(JSON.Encode.int(index))))
  })

  testAsync("GET /events with count=0, or a count that isn't a number", async t => {
    let response = await send("/events?count=0")
    t->expect(response.status)->Expect.toBe(200)
    t->expect(await response->Response.text)->Expect.toBe("")

    // Falls back to the default of 5.
    let response = await send("/events?count=lots&intervalMs=0")
    let lines = (await response->Response.text)->String.trim->String.split("\n")
    t->expect(lines->Array.length)->Expect.toBe(5)
  })

  testAsync("notes are shared state, and adding one needs a token", async t => {
    let app = Routes.make()
    let post = (~headers=dict{}, body) => send(~app, "/notes", ~method="POST", ~headers, ~body)
    let authorized = dict{
      "authorization": "Bearer secret-token",
      "content-type": "application/json",
    }

    let response = await send(~app, "/notes")
    t->expect(await response->Response.json)->Expect.toEqual(JSON.parseOrThrow("[]"))

    let response = await post(`{"text":"no token"}`)
    t->expect(response.status)->Expect.toBe(401)
    t
    ->expect(response.headers->ResServer.HttpHeaders.get("www-authenticate"))
    ->Expect.toBe(Some("Bearer"))
    let response = await post(
      ~headers=dict{"authorization": "Bearer wrong", "content-type": "application/json"},
      `{"text":"x"}`,
    )
    t->expect(response.status)->Expect.toBe(401)

    let response = await post(~headers=authorized, `{"text":"first"}`)
    t->expect(response.status)->Expect.toBe(201)
    t
    ->expect(await response->Response.json)
    ->Expect.toEqual(JSON.parseOrThrow(`{"id":1,"text":"first","author":"ada"}`))

    // The note is there for later requests to the same application...
    let response = await send(~app, "/notes")
    t
    ->expect(await response->Response.json)
    ->Expect.toEqual(JSON.parseOrThrow(`[{"id":1,"text":"first","author":"ada"}]`))
    // ...and not for another one.
    let response = await send("/notes")
    t->expect(await response->Response.json)->Expect.toEqual(JSON.parseOrThrow("[]"))
  })

  testAsync("a token is only one that was issued, whatever it's called", async t => {
    // Names every JavaScript object has: none of them is a token.
    let names = ["constructor", "toString", "__proto__", "valueOf", "hasOwnProperty"]
    let statuses = []
    for index in 0 to names->Array.length - 1 {
      let response = await send(
        "/notes",
        ~method="POST",
        ~headers=dict{
          "authorization": `Bearer ${names->Array.getUnsafe(index)}`,
          "content-type": "application/json",
        },
        ~body=`{"text":"x"}`,
      )
      statuses->Array.push(response.status)
    }
    t->expect(statuses)->Expect.toEqual([401, 401, 401, 401, 401])
  })

  testAsync("POST /notes takes JSON only if it's sent as JSON", async t => {
    // A page on another site can make a browser send these two without
    // asking, with the visitor's credentials; not `application/json`.
    let post = (~contentType=?, body) => {
      let headers = dict{"authorization": "Bearer secret-token"}
      contentType->Option.forEach(contentType => headers->Dict.set("content-type", contentType))
      send("/notes", ~method="POST", ~headers, ~body)
    }
    let body = `{"text":"x"}`
    t->expect((await post(~contentType="text/plain", body)).status)->Expect.toBe(415)
    t
    ->expect((await post(~contentType="application/x-www-form-urlencoded", body)).status)
    ->Expect.toBe(415)
    t->expect((await post(body)).status)->Expect.toBe(415)
    t->expect((await post(~contentType="application/json", body)).status)->Expect.toBe(201)
    t
    ->expect((await post(~contentType="application/json; charset=utf-8", body)).status)
    ->Expect.toBe(201)
  })

  testAsync("the Bearer scheme is recognised whatever its case", async t => {
    let post = authorization =>
      send(
        "/notes",
        ~method="POST",
        ~headers=dict{"authorization": authorization, "content-type": "application/json"},
        ~body=`{"text":"x"}`,
      )
    t->expect((await post("bearer secret-token")).status)->Expect.toBe(201)
    t->expect((await post("BEARER secret-token")).status)->Expect.toBe(201)
    t->expect((await post("Basic secret-token")).status)->Expect.toBe(401)
    t->expect((await post("secret-token")).status)->Expect.toBe(401)
  })

  testAsync("POST /notes rejects a body that isn't what it expects", async t => {
    let post = body =>
      send(
        "/notes",
        ~method="POST",
        ~headers=dict{
          "authorization": "Bearer secret-token",
          "content-type": "application/json",
        },
        ~body,
      )
    t->expect((await post("{nope")).status)->Expect.toBe(400)
    t->expect((await post(`{"text":42}`)).status)->Expect.toBe(400)
    t->expect((await post(`{"text":"  "}`)).status)->Expect.toBe(400)
    t->expect((await post(`["text"]`)).status)->Expect.toBe(400)
  })

  testAsync("unknown routes, and known routes with the wrong method, are a JSON 404", async t => {
    let response = await send("/nope")
    t->expect(response.status)->Expect.toBe(404)
    t
    ->expect(await response->Response.json)
    ->Expect.toEqual(JSON.parseOrThrow(`{"error":"No route for GET /nope"}`))

    let response = await send("/echo")
    t->expect(response.status)->Expect.toBe(404)
  })

  testAsync("a path with an encoded separator is refused, and logged", async t => {
    let lines = []
    let app = Routes.make(~log=line => lines->Array.push(line))
    let response = await send(~app, "/hello/..%2F..%2Fetc%2Fpasswd")
    t->expect(response.status)->Expect.toBe(400)
    t
    ->expect(lines->Array.map(line => line->String.split(" ")->Array.slice(~start=0, ~end=3)))
    ->Expect.toEqual([["GET", "/hello/..%2F..%2Fetc%2Fpasswd", "400"]])
  })

  testAsync("HEAD gets a GET route's headers without its body", async t => {
    let response = await send("/hello/Ada", ~method="HEAD")
    t->expect(response.status)->Expect.toBe(200)
    t->expect(response->contentType)->Expect.toBe(Some("text/plain; charset=utf-8"))
    t->expect(await response->Response.text)->Expect.toBe("")
    // The route for everything else still answers what no GET route does.
    t->expect((await send("/nope", ~method="HEAD")).status)->Expect.toBe(404)
  })

  testAsync("a line is logged per request when a logger is given", async t => {
    let lines = []
    let app = Routes.make(~log=line => lines->Array.push(line))
    let _ = await send(~app, "/hello?name=Ada")
    t
    ->expect(lines->Array.map(line => line->String.startsWith("GET /hello?name=Ada 200 ")))
    ->Expect.toEqual([true])
  })
})
