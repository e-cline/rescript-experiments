%%raw("/** @vitest-environment jsdom */")

/***
A page from the server to a hydrated screen, in one process: `Page`'s HTML streamed into jsdom piece
by piece, as a browser would parse it (the inline scripts run as they're reached), and the real
`Bootstrap` hydrating `#root` from the rows. The server's nodes are the ones on screen, the
entrypoints work, and a boundary the server was still streaming hydrates once its segment arrives.
*/

open Vitest

open PageSupport

type reader = Streams.Reader.t

/** Applies a chunk of the page's body as the parser would: its nodes into the body, then its scripts, in order. */
let apply: string => unit = %raw(`text => {
  const holder = document.createElement("div");
  holder.innerHTML = text.replace(/<script>[^<]*<\/script>/g, "");
  for (const node of [...holder.childNodes]) document.body.appendChild(node);
  for (const [, code] of text.matchAll(/<script>([^<]*)<\/script>/g)) (0, eval)(code);
}`)

let reset: unit => unit = %raw(`() => {
  delete self.__weft;
  document.body.innerHTML = "";
}`)

/** Makes the document look still parsed, until the function it returns is called. */
let stillLoading: unit => unit => unit = %raw(`() => {
  Object.defineProperty(document, "readyState", {configurable: true, get: () => "loading"});
  return () => { delete document.readyState };
}`)

let rootOf: unit => WeftDom.Dom.element = %raw(`() => document.getElementById("root")`)
let query: string => WeftDom.Dom.element = %raw(`selector => document.querySelector(selector)`)
let allElements: unit => array<
  WeftDom.Dom.element,
> = %raw(`() => [...document.querySelectorAll("#root *")]`)
let sameElements: (array<WeftDom.Dom.element>, array<WeftDom.Dom.element>) => bool = %raw(`(a, b) =>
  a.length === b.length && a.every((node, index) => node === b[index])`)

type console
@val external console: console = "console"
@get external consoleError: console => 'a => unit = "error"
@set external setConsoleError: (console, string => unit) => unit = "error"

let settle = async () =>
  for _ in 1 to 5 {
    await Testing.tick()
    WeftDom.Client.act(() => ())
  }

let clicked = selector => {
  WeftDom.Client.act(() => WeftDom.Dom.click(query(selector)))
  WeftDom.Dom.textContent(query(selector))
}

describe("a server-rendered page", () => {
  testAsync("is hydrated by the bootstrap, as it streams in", async t => {
    reset()
    let warnings = []
    let original = console->consoleError
    console->setConsoleError(message => warnings->Array.push(message))
    let (ready, open_) = {
      let resolve = ref(() => ())
      let promise = Promise.make((done, _) => resolve := (() => done()))
      (promise, () => resolve.contents())
    }
    let assets = assets()
    let page = Page.toStream(
      <main>
        <h1> {string("Notes")} </h1>
        <span id="outer">
          <Counter label="outer" />
        </span>
        <Weft.Suspense fallback={<i> {string("loading")} </i>}>
          <Later ready>
            <section id="inner">
              <Counter label="inner" />
            </section>
          </Later>
        </Weft.Suspense>
      </main>,
      ~assets,
    )
    let reader = page->Streams.getReader
    let decoder = Streams.Decoder.make()
    let next = async () =>
      switch await reader->Streams.Reader.read {
      | {done: false, value} => Some(decoder->Streams.Decoder.decode(value, {stream: true}))
      | _ => None
      }
    // The head: nothing of the body yet.
    let _ = await next()
    // The shell, in #root, and the rows so far.
    switch await next() {
    | Some(body) => apply(body)
    | None => JsError.throwWithMessage("the page ended early")
    }
    let fromServer = allElements()
    let _ = await Bootstrap.start(
      ~loadModule=assets.loadModule->Option.getUnsafe,
      ~container=rootOf(),
      ~url="/",
      (),
    )
    await settle()
    // Hydrated: the same elements, and they work; the boundary is still the server's fallback.
    t->expect(sameElements(fromServer, allElements()))->Expect.toBe(true)
    t->expect(clicked("#outer button"))->Expect.toBe("outer: 1")
    t->expect(WeftDom.Dom.textContent(query("#root i")))->Expect.toBe("loading")
    // The boundary's content, as the server streams it.
    open_()
    let finished = ref(false)
    while !finished.contents {
      switch await next() {
      | Some(chunk) => apply(chunk)
      | None => finished := true
      }
    }
    await settle()
    t->expect(clicked("#inner button"))->Expect.toBe("inner: 1")
    t->expect(WeftDom.Dom.textContent(query("#outer button")))->Expect.toBe("outer: 1")
    console->setConsoleError(original)
    t->expect(warnings)->Expect.toEqual([])
  })

  testAsync("starts, when its script runs before #root has arrived, once it has", async t => {
    reset()
    let loaded = stillLoading()
    let assets = assets()
    let html = await Testing.readAll(
      Page.toStream(
        <main>
          <Counter label="early" />
        </main>,
        ~assets,
      ),
    )
    // The bootstrap first, as an `async` script can be: no #root yet.
    Bootstrap.main(assets.loadModule->Option.getUnsafe, _ => ())
    apply(html->String.slice(~start=html->String.indexOf("<body>") + String.length("<body>")))
    await settle()
    loaded()
    t->expect(clicked("#root button"))->Expect.toBe("early: 1")
  })

  testAsync(
    "stops when its signal is aborted: its root unmounted, the history no longer followed",
    async t => {
      reset()
      let assets = assets()
      let html = await Testing.readAll(
        Page.toStream(
          <main>
            <Counter label="stopped" />
          </main>,
          ~assets,
        ),
      )
      apply(html->String.slice(~start=html->String.indexOf("<body>") + String.length("<body>")))
      let controller = Streams.Controller.make()
      let fetched = []
      let _ = await Bootstrap.start(
        ~loadModule=assets.loadModule->Option.getUnsafe,
        ~fetch=(url, ~signal as _) => {
          fetched->Array.push(url)
          Promise.make((_, _) => ())
        },
        ~container=rootOf(),
        ~url="/",
        ~signal=controller->Streams.Controller.signal,
        (),
      )
      await settle()
      t->expect(clicked("#root button"))->Expect.toBe("stopped: 1")
      WeftDom.Client.act(() => controller->Streams.Controller.abort)
      t->expect(WeftDom.Dom.innerHTML(rootOf()))->Expect.toBe("")
      // Going back or forward is another page's business now.
      let popState: unit => unit = %raw(`() => window.dispatchEvent(new PopStateEvent("popstate"))`)
      popState()
      await settle()
      t->expect(fetched)->Expect.toEqual([])
    },
  )
})

let stylesheetLinks: string => array<WeftDom.Dom.element> = %raw(`href =>
  [...document.querySelectorAll('link[rel="stylesheet"]')].filter(link => link.getAttribute("href") === href)`)
let fireLoad: WeftDom.Dom.element => unit = %raw(`link => link.dispatchEvent(new Event("load"))`)
let resetStylesheets: unit => unit = %raw(`() => {
  document.head.innerHTML = "";
  delete globalThis.__weftCss;
}`)
let exists = selector =>
  !Nullable.isNullable(%raw(`selector => document.querySelector(selector)`)(selector))

describe("a server-rendered page with stylesheets", () => {
  testAsync(
    "swaps a boundary in, and hydrates it, once its sheet has loaded, from one link",
    async t => {
      reset()
      resetStylesheets()
      let (ready, open_) = {
        let resolve = ref(() => ())
        let promise = Promise.make((done, _) => resolve := (() => done()))
        (promise, () => resolve.contents())
      }
      let assets = {
        ...assets(),
        sheets: dict{"wdddddd": {Render.href: "/d.css", dependencies: []}},
      }
      let page = Page.toStream(
        <main>
          <Weft.Suspense fallback={<i> {string("loading")} </i>}>
            <Later ready>
              <section id="styled" className="D-z_wdddddd">
                <Counter label="styled" />
              </section>
            </Later>
          </Weft.Suspense>
        </main>,
        ~assets,
      )
      let reader = page->Streams.getReader
      let decoder = Streams.Decoder.make()
      let next = async () =>
        switch await reader->Streams.Reader.read {
        | {done: false, value} => Some(decoder->Streams.Decoder.decode(value, {stream: true}))
        | _ => None
        }
      let _ = await next()
      switch await next() {
      | Some(body) => apply(body)
      | None => JsError.throwWithMessage("the page ended early")
      }
      let _ = await Bootstrap.start(
        ~loadModule=assets.loadModule->Option.getUnsafe,
        ~container=rootOf(),
        ~url="/",
        (),
      )
      await settle()
      open_()
      let finished = ref(false)
      while !finished.contents {
        switch await next() {
        | Some(chunk) => apply(chunk)
        | None => finished := true
        }
      }
      await settle()
      // Its segment has arrived, and its rows; its sheet hasn't loaded: the fallback stays.
      t->expect(exists("#styled"))->Expect.toBe(false)
      t->expect(WeftDom.Dom.textContent(query("#root i")))->Expect.toBe("loading")
      // One link, the runtime's and the client's both.
      let links = stylesheetLinks("/d.css")
      t->expect(Array.length(links))->Expect.toBe(1)
      fireLoad(links->Array.getUnsafe(0))
      await settle()
      t->expect(clicked("#styled button"))->Expect.toBe("styled: 1")
      t->expect(Array.length(stylesheetLinks("/d.css")))->Expect.toBe(1)
    },
  )
})
