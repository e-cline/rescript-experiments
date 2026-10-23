/***
`Page` with its HTML (assets with a `loadModule`): the shell in `#root`, the rows after it, each
pending boundary's segment as it's ready, and today's page (an empty `#root`, the rows) when the
shell or the root row fails, with each error reported once.
*/

open Vitest
open PageSupport

let indexOf = (html, text) => html->String.indexOf(text)

@get external bodyOf: Response.t => Streams.t = "body"

let reporting = () => {
  let reported = []
  let onError = error => {
    reported->Array.push(Weft.ErrorBoundary.message(error))
    Some("d")
  }
  (reported, onError)
}

describe("a page with its HTML", () => {
  testAsync("writes the shell in #root, after its chunks' preloads, then the rows", async t => {
    let html = await Testing.readAll(
      Page.toStream(
        <main>
          <h1> {string("Hello")} </h1>
          <Counter label="clicks" />
        </main>,
        ~assets=assets(),
      ),
    )
    let root = indexOf(
      html,
      `<div id="root" data-weft-html=""><main><h1>Hello</h1><button class="counter">clicks: 0</button></main></div>`,
    )
    t->expect(root > 0)->Expect.toBe(true)
    t
    ->expect(indexOf(html, `<link rel="modulepreload" href="/assets/Dom.js">`) < root)
    ->Expect.toBe(true)
    // Every row after the shell, so the bootstrap never sees one before #root is parsed.
    t->expect(indexOf(html, "<script>(self.__weft") > root)->Expect.toBe(true)
    t->expect(html->String.endsWith(`.push(null)</script></body></html>`))->Expect.toBe(true)
  })

  testAsync(
    "writes a pending boundary's fallback, then its content as a segment, before the end",
    async t => {
      let (ready, open_) = {
        let resolve = ref(() => ())
        let promise = Promise.make((done, _) => resolve := (() => done()))
        (promise, () => resolve.contents())
      }
      let reader = Page.toStream(
        <Weft.Suspense fallback={<i> {string("loading")} </i>}>
          <Later ready>
            <p> {string("later")} </p>
          </Later>
        </Weft.Suspense>,
        ~assets=assets(),
      )->Streams.getReader
      let decoder = Streams.Decoder.make()
      let html = ref("")
      let finished = ref(false)
      while !finished.contents {
        switch await reader->Streams.Reader.read {
        | {done: false, value} =>
          html := html.contents ++ decoder->Streams.Decoder.decode(value, {stream: true})

          // The content only once the shell is out.
          if html.contents->String.includes(`id="root"`) {
            open_()
          }
        | _ => finished := true
        }
      }
      let html = html.contents
      t
      ->expect(
        html->String.includes(`<div id="root" data-weft-html=""><!--$?--><template id="wb:0"></template><i>loading</i><!--/$--></div>`),
      )
      ->Expect.toBe(true)
      let segment = indexOf(
        html,
        `<template id="ws:0"><p>later</p></template><script>$weftSwap(0)</script>`,
      )
      t->expect(segment > 0)->Expect.toBe(true)
      t->expect(segment < indexOf(html, ".push(null)"))->Expect.toBe(true)
    },
  )

  testAsync("gives entrypoints a page, at the request's URL, that refuses to fetch", async t => {
    let html = await Testing.readAll(
      Page.toStream(<Where />, ~assets=assets(), ~url="/notes/1?x=2"),
    )
    t
    ->expect(html->String.includes(`data-weft-html=""><code>/notes/1?x=2</code></div>`))
    ->Expect.toBe(true)
    let (reported, onError) = reporting()
    let html = await Testing.readAll(Page.toStream(<Fetches />, ~assets=assets(), ~onError))
    // Outside every boundary: today's page, for the client.
    t->expect(html->String.includes(`<div id="root"></div>`))->Expect.toBe(true)
    t
    ->expect(reported)
    ->Expect.toEqual([
      "WeftServer: the page was asked to fetch while it was rendered on the server (navigate, refresh, or a refetch): call these from handlers and effects, which only run in the browser",
    ])
  })

  testAsync(
    "falls back to the rows alone when an entrypoint fails outside every boundary",
    async t => {
      let (reported, onError) = reporting()
      let html = await Testing.readAll(
        Page.toStream(
          <div>
            <Throws />
          </div>,
          ~assets=assets(),
          ~onError,
        ),
      )
      t
      ->expect(
        html->String.includes(`<body><link rel="modulepreload" href="/assets/Dom.js"><div id="root"></div><script>`),
      )
      ->Expect.toBe(true)
      t->expect(reported)->Expect.toEqual(["the entrypoint failed"])
    },
  )

  testAsync("falls back when the root row fails, reporting the error once", async t => {
    let (reported, onError) = reporting()
    let html = await Testing.readAll(
      Page.toStream(<ServerFails message="the server failed" />, ~assets=assets(), ~onError),
    )
    t->expect(html->String.includes(`<div id="root"></div>`))->Expect.toBe(true)
    t->expect(reported)->Expect.toEqual(["the server failed"])
  })

  testAsync(
    "writes a boundary a server component failed in as failed, reporting it once",
    async t => {
      let (reported, onError) = reporting()
      let html = await Testing.readAll(
        Page.toStream(
          <Weft.Suspense fallback={string("fallback")}>
            <ServerFails message="inside" />
          </Weft.Suspense>,
          ~assets=assets(),
          ~onError,
        ),
      )
      t
      ->expect(
        html->String.includes(`<!--$!--><template data-digest="d" data-message="inside"></template>fallback<!--/$-->`),
      )
      ->Expect.toBe(true)
      t->expect(reported)->Expect.toEqual(["inside"])
    },
  )

  testAsync("is the rows alone with ~html=false, or assets without a loadModule", async t => {
    let element = <p> {string("x")} </p>
    let off = await Testing.readAll(Page.toStream(element, ~assets=assets(), ~html=false))
    t->expect(off->String.includes(`</head><body><div id="root"></div><script>`))->Expect.toBe(true)
    let assets = {...assets(), loadModule: ?None}
    let without = await Testing.readAll(Page.toStream(element, ~assets))
    t
    ->expect(without->String.includes(`</head><body><div id="root"></div><script>`))
    ->Expect.toBe(true)
  })

  testAsync("takes the page's URL from the request, in respond", async t => {
    let response = Page.respond(
      %raw(`new Request("http://test.local/notes/7?tab=a")`),
      <Where />,
      ~assets=assets(),
    )
    let html = await Testing.readAll(bodyOf(response))
    t->expect(html->String.includes("<code>/notes/7?tab=a</code>"))->Expect.toBe(true)
  })
})
