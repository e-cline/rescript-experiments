@@jsxConfig({version: 4, module_: "Jsx"})

/***
Segments that need stylesheets: the swap waits for them (the page's link for each, or a new one in
the head), so a boundary's content never shows without its CSS, in jsdom.
*/

open Vitest
open DomSupport

let string = Jsx.string

let deferred = (): (promise<'a>, 'a => unit) => {
  let resolve = ref(_ => ())
  let promise = Promise.make((done, _) => resolve := done)
  (promise, value => resolve.contents(value))
}

let tick = () => Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)

module Waits = {
  @weft.component
  let make = (~promise: promise<string>) =>
    <em className="W-x_waaaaaa"> {string(Weft.Hooks.use(promise))} </em>
}

module Inner = {
  @weft.component
  let make = (~promise: promise<string>) => <b> {string(Weft.Hooks.use(promise))} </b>
}

/** Content that needs `/a.css`, with a boundary of its own inside. */
module Outer = {
  @weft.component
  let make = (~promise: promise<string>, ~inner: promise<string>) =>
    <em className="W-x_waaaaaa">
      {string(Weft.Hooks.use(promise))}
      <Weft.Suspense fallback={<i> {string("inner loading")} </i>}>
        <Inner promise=inner />
      </Weft.Suspense>
    </em>
}

type element
let linkFor: string => Nullable.t<element> = %raw(`href =>
  [...document.querySelectorAll('link[rel="stylesheet"]')].find(link => link.getAttribute("href") === href) ?? null`)
let fire: (
  element,
  string,
) => unit = %raw(`(element, type) => element.dispatchEvent(new Event(type))`)
let addLoadedLink: string => unit = %raw(`href => {
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.setAttribute("href", href);
  // A link whose sheet has loaded, as the browser has it (jsdom loads none).
  Object.defineProperty(link, "sheet", {value: {}});
  document.head.append(link);
}`)
let addFailedLink: string => element = %raw(`href => {
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.setAttribute("href", href);
  // A link that failed, as the server's are once they have: no sheet, and \`weftSettled\` (its
  // \`onerror\`, which jsdom doesn't run).
  link.weftSettled = 1;
  document.head.append(link);
  return link;
}`)
let reset: unit => unit = %raw(`() => {
  document.head.innerHTML = "";
  document.body.innerHTML = "";
  delete globalThis.__weftCss;
}`)
let state: string => Nullable.t<{
  "loaded": bool,
}> = %raw(`href => globalThis.__weftCss?.[href] ?? null`)

/**
A page with a boundary whose content needs `/a.css`, and has a boundary in it: the inner one's
segment comes after the outer's, with the inner content (or, `~fail`, an error).
*/
let pageWithNested = async (~fail=false) => {
  let (outer, resolveOuter) = deferred()
  let settleInner = ref(() => ())
  let innerPromise = Promise.make((resolve, reject) =>
    settleInner := (() => fail ? reject(Failure("inner failed")) : resolve("inner done"))
  )
  let rendering = Html.render(
    <Weft.Suspense fallback={<i> {string("outer loading")} </i>}>
      <Outer promise=outer inner=innerPromise />
    </Weft.Suspense>,
    ~onError=_ => None,
    ~stylesheetsOf=markup => markup->String.includes("_waaaaaa") ? ["/a.css"] : [],
  )
  let container = page(await rendering->Html.shell)
  let rest = chunks(rendering->Html.rest)
  resolveOuter("outer done")
  await tick()
  await tick()
  settleInner.contents()
  (container, await rest)
}

/** A page with one boundary whose content needs `/a.css` (and `/base.css`, which it depends on). */
let pageWithSegment = async () => {
  let (promise, resolve) = deferred()
  let rendering = Html.render(
    <Weft.Suspense fallback={<i> {string("loading")} </i>}>
      <Waits promise />
    </Weft.Suspense>,
    ~stylesheetsOf=markup => markup->String.includes("_waaaaaa") ? ["/base.css", "/a.css"] : [],
  )
  let container = page(await rendering->Html.shell)
  let rest = chunks(rendering->Html.rest)
  resolve("done")
  (container, (await rest)->Array.join(""))
}

describe("a segment that needs stylesheets", () => {
  beforeEach(reset)

  testAsync("names them in its swap", async t => {
    let (_, segment) = await pageWithSegment()
    t->expect(segment)->Expect.String.toContain(`$weftSwap(0,["/base.css","/a.css"])`)
  })

  testAsync("swaps in only once they've loaded, adding their links to the head", async t => {
    let (container, segment) = await pageWithSegment()
    arrive(segment)
    run(segment)
    await tick()
    t->expect(markup(container))->Expect.String.toContain("loading")
    let (base, a) = (linkFor("/base.css"), linkFor("/a.css"))
    t->expect((Nullable.isNullable(base), Nullable.isNullable(a)))->Expect.toEqual((false, false))
    fire(Nullable.getUnsafe(base), "load")
    await tick()
    t->expect(markup(container))->Expect.String.toContain("loading")
    // One that fails counts as loaded: the content shows, unstyled, rather than never.
    fire(Nullable.getUnsafe(a), "error")
    await tick()
    t->expect(markup(container))->Expect.String.toContain(`<em class="W-x_waaaaaa">done</em>`)
  })

  testAsync(
    "doesn't wait for the page's own links that have loaded, and shares their state",
    async t => {
      addLoadedLink("/base.css")
      addLoadedLink("/a.css")
      let (container, segment) = await pageWithSegment()
      arrive(segment)
      run(segment)
      t->expect(markup(container))->Expect.String.toContain(">done</em>")
      // The state `WeftCss.Sheets` reads, so the client doesn't load them again.
      t
      ->expect(state("/a.css")->Nullable.toOption->Option.map(state => state["loaded"]))
      ->Expect.toEqual(Some(true))
      t->expect(WeftCss.Sheets.isLoaded("/a.css"))->Expect.toBe(true)
    },
  )

  testAsync("doesn't wait for the page's link that has failed already", async t => {
    let _ = addFailedLink("/a.css")
    addLoadedLink("/base.css")
    let (container, segment) = await pageWithSegment()
    arrive(segment)
    run(segment)
    t->expect(markup(container))->Expect.String.toContain(">done</em>")
  })

  testAsync(
    "swaps in a boundary inside one still waiting for its sheets, once that one is in",
    async t => {
      let (container, segments) = await pageWithNested()
      t->expect(segments->Array.length)->Expect.toBe(2)
      // The inner one's segment arrives (and runs) while the outer waits for `/a.css`.
      segments->Array.forEach(
        segment => {
          arrive(segment)
          run(segment)
        },
      )
      await tick()
      t->expect(markup(container))->Expect.String.toContain("outer loading")
      fire(Nullable.getUnsafe(linkFor("/a.css")), "load")
      await tick()
      t->expect(markup(container))->Expect.String.toContain("outer done")
      t->expect(markup(container))->Expect.String.toContain("<b>inner done</b>")
      t->expect(markup(container)->String.includes("inner loading"))->Expect.toBe(false)
    },
  )

  testAsync(
    "fails a boundary inside one still waiting for its sheets, once that one is in",
    async t => {
      let (container, segments) = await pageWithNested(~fail=true)
      segments->Array.forEach(
        segment => {
          arrive(segment)
          run(segment)
        },
      )
      await tick()
      fire(Nullable.getUnsafe(linkFor("/a.css")), "load")
      await tick()
      t->expect(markup(container))->Expect.String.toContain("<!--$!-->")
    },
  )

  testAsync("waits for a sheet the client is loading, through the shared state", async t => {
    let loading = WeftCss.Sheets.load("/a.css")
    addLoadedLink("/base.css")
    let (container, segment) = await pageWithSegment()
    arrive(segment)
    run(segment)
    await tick()
    t->expect(markup(container))->Expect.String.toContain("loading")
    fire(Nullable.getUnsafe(linkFor("/a.css")), "load")
    await loading
    await tick()
    t->expect(markup(container))->Expect.String.toContain(">done</em>")
  })
})
