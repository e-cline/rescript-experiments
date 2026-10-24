@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/***
`Page`, the HTML a first request gets, and `Bootstrap.rows`, which reads the payload back out of
it: the rows the HTML carries are the payload's, whatever is in them, and they reach the bootstrap
whether its scripts ran before or after it started.
*/

open Vitest
open Support

let assets: Page.assets = {
  scripts: ["/@vite/client", "/src/Decoder.res.js"],
  preloads: ["/assets/runtime.js"],
  styles: ["/assets/app.css"],
  entrypoints: dict{"test/Entrypoints.res": ["/assets/Entrypoints.js", "/assets/shared.js"]},
}

/** The rows a page's inline scripts push, in order (`None` for the end), as a browser would run them. */
let pushedRows = html => {
  let pushes = []
  html
  ->String.split("<script>(self.__weft||=[]).push(")
  ->Array.slice(~start=1)
  ->Array.forEach(rest => {
    let argument = rest->String.slice(~start=0, ~end=rest->String.indexOf(")</script>"))
    pushes->Array.push(
      argument == "null"
        ? None
        : Some(JSON.parseOrThrow(argument)->JSON.Decode.string->Option.getOrThrow),
    )
  })
  pushes
}

describe("Page.toStream", () => {
  testAsync("writes the head, the root, then each row, then the end", async t => {
    let html = await Testing.readAll(
      Page.toStream(<p id="x"> {text("hello")} </p>, ~assets, ~title="A <title>"),
    )
    t
    ->expect(html->String.startsWith(`<!doctype html><html lang="en"><head><meta charset="utf-8">`))
    ->Expect.toBe(true)
    t->expect(html->String.includes("<title>A &lt;title&gt;</title>"))->Expect.toBe(true)
    t
    ->expect(html->String.includes(`<link rel="stylesheet" href="/assets/app.css">`))
    ->Expect.toBe(true)
    t
    ->expect(html->String.includes(`<link rel="modulepreload" href="/assets/runtime.js">`))
    ->Expect.toBe(true)
    t
    ->expect(
      html->String.includes(`<script type="module" async src="/src/Decoder.res.js"></script>`),
    )
    ->Expect.toBe(true)
    t
    ->expect(html->String.includes(`</head><body><div id="root"></div><script>`))
    ->Expect.toBe(true)
    t->expect(html->String.endsWith(`.push(null)</script></body></html>`))->Expect.toBe(true)
    let payload = await Testing.readAll(Render.toStream(<p id="x"> {text("hello")} </p>))
    t->expect(pushedRows(html))->Expect.toEqual([Some(payload), None])
  })

  testAsync("carries rows that would end a script, or hold line separators, intact", async t => {
    let awkward = "</script><script>alert(1)</script> <!--     \"quoted\" \\ end"
    let element = <p id="x"> {text(awkward)} </p>
    let html = await Testing.readAll(Page.toStream(element, ~assets))
    // Exactly one script ends per row script, so nothing in the data ended one.
    let scripts = html->String.split("</script>")->Array.length - 1
    t->expect(scripts)->Expect.toBe(Array.length(assets.scripts) + 2)
    t->expect(html->String.includes(" "))->Expect.toBe(false)
    let payload = await Testing.readAll(Render.toStream(element))
    t->expect(pushedRows(html))->Expect.toEqual([Some(payload), None])
  })

  testAsync("preloads an entrypoint's chunks before the first row using it, once", async t => {
    let html = await Testing.readAll(
      Page.toStream(
        <div>
          <Counter label="a" />
          <Counter label="b" />
          <Probe name="p" value=1 />
        </div>,
        ~assets,
      ),
    )
    let preload = `<link rel="modulepreload" href="/assets/Entrypoints.js"><link rel="modulepreload" href="/assets/shared.js">`
    t->expect(html->String.split(preload)->Array.length)->Expect.toBe(2)
    t
    ->expect(html->String.indexOf(preload) < html->String.indexOf(`push("1:E`))
    ->Expect.toBe(true)
  })

  testAsync("streams rows under a boundary as they're ready, after the rest", async t => {
    let ready = Deferred.make()
    let pipe = Testing.pipe(
      Page.toStream(
        <Weft.Suspense fallback=loading>
          <Async ready=ready.promise>
            <b id="late"> {text("late")} </b>
          </Async>
        </Weft.Suspense>,
        ~assets,
      ),
    )
    await settle()
    t->expect(Testing.written(pipe)->String.includes("late"))->Expect.toBe(false)
    t->expect(Testing.written(pipe)->String.includes(`push(null)`))->Expect.toBe(false)
    ready.resolve()
    await Testing.finished(pipe)
    t->expect(Testing.written(pipe)->String.includes("late"))->Expect.toBe(true)
    t
    ->expect(Testing.written(pipe)->String.endsWith(`push(null)</script></body></html>`))
    ->Expect.toBe(true)
  })
})

describe("Page.rowScript", () => {
  test("pushes a row, or the end", t => {
    t
    ->expect(Page.rowScript(Some("0:J1\n")))
    ->Expect.toBe(`<script>(self.__weft||=[]).push("0:J1\\n")</script>`)
    t->expect(Page.rowScript(None))->Expect.toBe(`<script>(self.__weft||=[]).push(null)</script>`)
  })
})

@new external makeRequest: (string, {..}) => Request.t = "Request"
@get external responseHeaders: Response.t => FetchTypes.headers = "headers"
@send external responseText: Response.t => promise<string> = "text"

describe("Page.respond", () => {
  test("knows which requests want the bare payload", t => {
    t->expect(Page.wantsPayload(Some(Payload.contentType)))->Expect.toBe(true)
    t->expect(Page.wantsPayload(Some(`text/html, ${Payload.contentType};q=0.9`)))->Expect.toBe(true)
    t->expect(Page.wantsPayload(Some("text/html,*/*")))->Expect.toBe(false)
    t->expect(Page.wantsPayload(None))->Expect.toBe(false)
  })

  testAsync("answers with the payload, or the page, by the Accept header", async t => {
    let element = <p id="x"> {text("hello")} </p>
    let payloadResponse = Page.respond(
      makeRequest("http://localhost/x", {"headers": {"accept": Payload.contentType}}),
      element,
      ~assets,
    )
    let header = (response, name) => response->responseHeaders->Headers.get(name)->Null.toOption
    t->expect(header(payloadResponse, "content-type"))->Expect.toEqual(Some(Payload.contentType))
    t->expect(header(payloadResponse, "vary"))->Expect.toEqual(Some("Accept"))
    t->expect(header(payloadResponse, "cache-control"))->Expect.toEqual(Some(Payload.cacheControl))
    t
    ->expect(await payloadResponse->responseText)
    ->Expect.toBe(await Testing.readAll(Render.toStream(element)))
    let page = Page.respond(
      makeRequest("http://localhost/x", {"headers": {"accept": "text/html"}}),
      element,
      ~assets,
    )
    t->expect(header(page, "content-type"))->Expect.toEqual(Some("text/html; charset=utf-8"))
    t->expect(header(page, "cache-control"))->Expect.toEqual(Some("no-store"))
    t
    ->expect((await page->responseText)->String.includes(`<div id="root"></div>`))
    ->Expect.toBe(true)
  })
})

describe("Bootstrap.rows", () => {
  testAsync(
    "reads rows pushed before it started, then those pushed after, until the end",
    async t => {
      let target = {"__weft": [Nullable.make("0:J\"a\"\n"), Nullable.make("1:J2\n")]}
      let stream = Bootstrap.rows(target)
      let all = Testing.readAll(stream)
      // As the page's later scripts do.
      let push: (
        {..},
        Nullable.t<string>,
      ) => int = %raw(`(self, row) => (self.__weft ||= []).push(row)`)
      let pushOn = row => push(target, row)->ignore
      pushOn(Nullable.make("2:J3\n"))
      pushOn(Nullable.null)
      pushOn(Nullable.make("3:J4\n"))
      t->expect(await all)->Expect.toBe("0:J\"a\"\n1:J2\n2:J3\n")
    },
  )

  testAsync("a page's rows, read back, render as the element did", async t => {
    let element =
      <section id="page">
        <Counter label="a" />
        <Wrap id="w"> {text("text")} </Wrap>
      </section>
    let html = await Testing.readAll(Page.toStream(element, ~assets))
    let target = {"__weft": pushedRows(html)->Array.map(Nullable.fromOption)}
    let decoded = await makeClient()->Decoder.fromStream(Bootstrap.rows(target))
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, decoded)
    await settle()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(renderDirectly(element))
  })
})
