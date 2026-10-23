@@jsxConfig({version: 4, module_: "Jsx"})

/***
`Html`, the HTML renderer: what it writes for each kind of element and prop, how boundaries stream
(markers, segments, the runtime that swaps them in, in jsdom), errors, and, as the oracle, that the
DOM the HTML parses into is the DOM a client render of the same tree makes.
*/

open Vitest
open DomSupport

module Hooks = Weft.Hooks

let string = Jsx.string

let html = (~onError=?, element) => Html.renderToString(element, ~onError?)

/** The text of the error `f`'s promise rejects with. */
let rejection = async (f: unit => promise<'a>) =>
  switch await f() {
  | _ => None
  | exception JsExn(error) => JsExn.message(error)
  }

type console
@val external console: console = "console"
@get external consoleError: console => 'a => unit = "error"
@set external setConsoleError: (console, string => unit) => unit = "error"

/** What `f` logs with `console.error`, while it runs. */
let logged = async (f: unit => promise<'a>) => {
  let original = console->consoleError
  let messages = []
  console->setConsoleError(message => messages->Array.push(message))
  switch await f() {
  | _ => console->setConsoleError(original)
  | exception error =>
    console->setConsoleError(original)
    throw(error)
  }
  messages
}

/** A promise, and a way to resolve it. */
let deferred = (): (promise<'a>, 'a => unit) => {
  let resolve = ref(_ => ())
  let promise = Promise.make((done, _) => resolve := done)
  (promise, value => resolve.contents(value))
}

let tick = () => Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)

module Waits = {
  /** Suspends until `promise` resolves, then shows what it resolved to. */
  @weft.component
  let make = (~promise: promise<string>) => <em> {string(Hooks.use(promise))} </em>
}

module Fails = {
  @weft.component
  let make = (~message: string) => JsError.throwWithMessage(message)
}

let theme = Weft.Context.make("plain")

module Themed = {
  @weft.component
  let make = () => <i> {string(Hooks.useContext(theme))} </i>
}

let themeProvider = (value, children) =>
  Weft.JsxCore.jsx(Weft.Context.provider(theme), {value, children})

describe("host elements and props", () => {
  testAsync("writes tags, attributes by DomProps' names, and booleans", async t => {
    t
    ->expect(
      await html(
        <div id="a" className="b c" title="t" hidden=true tabIndex=2>
          <label htmlFor="x"> {string("L")} </label>
          <button disabled=false> {string("B")} </button>
        </div>,
      ),
    )
    ->Expect.toBe(`<div id="a" class="b c" title="t" hidden="" tabindex="2"><label for="x">L</label><button>B</button></div>`)
  })

  testAsync("leaves out event handlers and refs", async t => {
    let ref: Weft.Ref.t<Nullable.t<Dom.element>> = {current: Nullable.null}
    t
    ->expect(await html(<button onClick={_ => ()} ref> {string("go")} </button>))
    ->Expect.toBe("<button>go</button>")
  })

  testAsync("writes style as CSS, in kebab case", async t => {
    t
    ->expect(
      await html(
        <p
          style={dict{
            "backgroundColor": "red",
            "--accent": "blue",
            "font-size": "2em",
            "WebkitTransform": "none",
            "msFilter": "x",
          }}
        />,
      ),
    )
    ->Expect.toBe(`<p style="background-color: red; --accent: blue; font-size: 2em; -webkit-transform: none; -ms-filter: x;"></p>`)
    t->expect(await html(<p style={dict{}} />))->Expect.toBe("<p></p>")
  })

  testAsync("escapes text and attributes, so nothing ends a tag or a script", async t => {
    t
    ->expect(
      await html(
        <p title={`"quoted" & 'single' <b>`}>
          {string(`</script><script>alert(1)</script> & <`)}
        </p>,
      ),
    )
    ->Expect.toBe(`<p title="&quot;quoted&quot; &amp; &#39;single&#39; &lt;b&gt;">&lt;/script&gt;&lt;script&gt;alert(1)&lt;/script&gt; &amp; &lt;</p>`)
  })

  testAsync("writes void elements without a closing tag, and refuses their children", async t => {
    t
    ->expect(
      await html(
        <div>
          <br />
          <input type_="text" />
        </div>,
      ),
    )
    ->Expect.toBe(`<div><br><input type="text"></div>`)
    t
    ->expect(await rejection(() => html(<br> {string("x")} </br>)))
    ->Expect.toEqual(Some("WeftDom: a <br> can't have children, at <br>"))
  })

  testAsync("refuses a tag that isn't one, and script or style content", async t => {
    let bad = Weft.JsxCore.hostJsx("div onclick=x", ({}: DomProps.props))
    t
    ->expect(await rejection(() => html(bad)))
    ->Expect.toEqual(Some(`WeftDom: "div onclick=x" isn't a tag name, at the root`))
    let script = Weft.JsxCore.hostJsx("script", ({children: string("alert(1)")}: DomProps.props))
    t
    ->expect(await rejection(() => html(script)))
    ->Expect.toEqual(
      Some(
        "WeftDom: a <script>'s content isn't HTML, so it can't be rendered from children, at <script>",
      ),
    )
  })

  testAsync(
    "writes value and checked as the attributes that give the same initial state",
    async t => {
      t
      ->expect(
        await html(
          <form>
            <input value="typed" />
            <input type_="checkbox" checked=true />
            <input type_="checkbox" checked=false />
            <textarea value={"\nstarts with a newline"} />
          </form>,
        ),
      )
      ->Expect.toBe(`<form><input value="typed"><input type="checkbox" checked=""><input type="checkbox"><textarea>\n\nstarts with a newline</textarea></form>`)
      // A select's value is its option's `selected`, by the option's value or its text.
      t
      ->expect(
        await html(
          <select value="b">
            <option value="a"> {string("A")} </option>
            <option value="b"> {string("B")} </option>
            <option> {string("b")} </option>
          </select>,
        ),
      )
      ->Expect.toBe(`<select><option value="a">A</option><option value="b" selected="">B</option><option selected="">b</option></select>`)
    },
  )
})

describe("text, components and the rest", () => {
  testAsync(
    "separates texts in a row, wherever they come from, and writes nothing for empty text",
    async t => {
      module Word = {
        @weft.component
        let make = (~word: string) => string(word)
      }
      t
      ->expect(
        await html(
          <p>
            {string("a")}
            {string("b")}
            {string("")}
            <Word word="c" />
            <> {string("d")} </>
            <b> {string("e")} </b>
            {string("f")}
          </p>,
        ),
      )
      ->Expect.toBe("<p>a<!-- -->b<!-- -->c<!-- -->d<b>e</b>f</p>")
    },
  )

  testAsync("calls components with their initial state, providers' values, and memo", async t => {
    module Counter = {
      @weft.component
      let make = (~start: int) => {
        let (count, _) = Hooks.useState(() => start)
        Hooks.useEffect0(() => JsError.throwWithMessage("effects don't run on the server"))
        <b> {Jsx.int(count)} </b>
      }
    }
    let memoized = Weft.Memo.memo(Counter.make)
    t
    ->expect(
      await html(
        <div>
          <Counter start=3 />
          {Weft.JsxCore.jsx(memoized, {start: 4})}
          <Themed />
          {themeProvider("dark", <Themed />)}
          {themeProvider("outer", themeProvider("inner", <Themed />))}
        </div>,
      ),
    )
    ->Expect.toBe("<div><b>3</b><b>4</b><i>plain</i><i>dark</i><i>inner</i></div>")
  })

  testAsync("renders nothing for a portal, and an error boundary's children", async t => {
    let elsewhere = Dom.createElement(Dom.document, "div")
    t
    ->expect(
      await html(
        <div>
          {Portal.create(<p> {string("away")} </p>, ~container=elsewhere)}
          <Weft.ErrorBoundary fallback={(~error as _, ~reset as _) => string("fallback")}>
            {string("children")}
          </Weft.ErrorBoundary>
        </div>,
      ),
    )
    ->Expect.toBe("<div>children</div>")
  })

  testAsync("waits for what suspends outside every boundary", async t => {
    let (promise, resolve) = deferred()
    let rendered = html(
      <div>
        <Waits promise />
      </div>,
    )
    await tick()
    resolve("ready")
    t->expect(await rendered)->Expect.toBe("<div><em>ready</em></div>")
  })

  testAsync("waits for sibling suspensions together, not one after the other", async t => {
    let renders = ref(0)
    module Counted = {
      @weft.component
      let make = (~promise: promise<string>) => {
        renders := renders.contents + 1
        <em> {string(Hooks.use(promise))} </em>
      }
    }
    let (first, resolveFirst) = deferred()
    let (second, resolveSecond) = deferred()
    let rendered = html(
      <div>
        <Counted promise=first />
        <Counted promise=second />
      </div>,
    )
    await tick()
    resolveSecond("2")
    resolveFirst("1")
    t->expect(await rendered)->Expect.toBe("<div><em>1</em><em>2</em></div>")
    // One attempt finding both, one rendering both.
    t->expect(renders.contents)->Expect.toBe(4)
  })

  testAsync(
    "renders a resolved Lazy element as what it resolved to, and waits for one that isn't",
    async t => {
      let (promise, resolve) = deferred()
      let lazy_ = Weft.Lazy.fromPromise(promise)
      let rendered = html(<div> lazy_ </div>)
      await tick()
      resolve(<b> {string("lazy")} </b>)
      t->expect(await rendered)->Expect.toBe("<div><b>lazy</b></div>")
    },
  )

  testAsync("warns about nesting the parser would repair", async t => {
    let messages = await logged(
      async () => {
        let _ = await html(
          <div>
            <p>
              <span>
                <div />
              </span>
            </p>
            <table>
              <tr>
                <td />
              </tr>
            </table>
          </div>,
        )
      },
    )
    t
    ->expect(messages)
    ->Expect.toEqual([
      "WeftDom: <div> can't be inside a <p>: the parser ends the <p> before it, so the page's HTML wouldn't hydrate as rendered. At <div><p><span>.",
      "WeftDom: a <tr> straight in a <table> gets a <tbody> from the parser: write the <tbody>, so the page's HTML wouldn't hydrate as rendered. At <div><table>.",
    ])
  })
})

describe("boundaries, all at once (renderToString)", () => {
  testAsync("writes a boundary's content between markers, waiting for it", async t => {
    let (promise, resolve) = deferred()
    let rendered = html(
      <div>
        <Weft.Suspense fallback={string("loading")}>
          <Waits promise />
        </Weft.Suspense>
      </div>,
    )
    await tick()
    resolve("done")
    t->expect(await rendered)->Expect.toBe("<div><!--$--><em>done</em><!--/$--></div>")
  })

  testAsync(
    "writes a failed boundary with its fallback and the digest, reporting it once",
    async t => {
      let reported = []
      let onError = error => {
        reported->Array.push(Weft.ErrorBoundary.message(error))
        Some("d1")
      }
      // A sibling outside the boundary suspends, so the whole thing renders twice: the failure is
      // still reported once.
      let (promise, resolve) = deferred()
      let rendered = html(
        ~onError,
        <div>
          <Waits promise />
          <Weft.Suspense fallback={string("fallback")}>
            <Fails message="boom" />
          </Weft.Suspense>
        </div>,
      )
      await tick()
      resolve("ok")
      t
      ->expect(await rendered)
      ->Expect.toBe(`<div><em>ok</em><!--$!--><template data-digest="d1" data-message="boom"></template>fallback<!--/$--></div>`)
      t->expect(reported)->Expect.toEqual(["boom"])
    },
  )

  testAsync("rejects for an error outside every boundary", async t => {
    t
    ->expect(
      await rejection(
        () =>
          html(
            ~onError=_ => None,
            <div>
              <Fails message="shell" />
            </div>,
          ),
      ),
    )
    ->Expect.toEqual(Some("shell"))
  })
})

let withoutRuntime = text => text->String.replace(`<script>${Html.runtime}</script>`, "")

type abortController
@new external makeController: unit => abortController = "AbortController"
@get external signalOf: abortController => Html.signal = "signal"
@send external abort: abortController => unit = "abort"

describe("streaming", () => {
  testAsync("writes a pending boundary's fallback in the shell, and its content after", async t => {
    let (promise, resolve) = deferred()
    let rendering = Html.render(
      <div>
        <Weft.Suspense fallback={<i> {string("loading")} </i>}>
          <Waits promise />
        </Weft.Suspense>
      </div>,
    )
    t
    ->expect(await rendering->Html.shell)
    ->Expect.toBe(`<div><!--$?--><template id="wb:0"></template><i>loading</i><!--/$--></div>`)
    let rest = chunks(rendering->Html.rest)
    resolve("done")
    let rest = await rest
    t
    ->expect(rest->Array.join("")->String.startsWith(`<script>${Html.runtime}</script>`))
    ->Expect.toBe(true)
    t
    ->expect(rest->Array.map(withoutRuntime))
    ->Expect.toEqual([`<template id="ws:0"><em>done</em></template><script>$weftSwap(0)</script>`])
  })

  testAsync("writes nested boundaries' segments after their parents'", async t => {
    let (outer, resolveOuter) = deferred()
    let (inner, resolveInner) = deferred()
    let rendering = Html.render(
      <Weft.Suspense fallback={string("outer loading")}>
        <Waits promise=outer />
        <Weft.Suspense fallback={string("inner loading")}>
          <Waits promise=inner />
        </Weft.Suspense>
      </Weft.Suspense>,
    )
    t
    ->expect(await rendering->Html.shell)
    ->Expect.toBe(`<!--$?--><template id="wb:0"></template>outer loading<!--/$-->`)
    let rest = chunks(rendering->Html.rest)
    // The inner one is ready first, but its anchor is in the outer one's segment.
    resolveInner("inner")
    await tick()
    resolveOuter("outer")
    t
    ->expect((await rest)->Array.map(withoutRuntime))
    ->Expect.toEqual([
      `<template id="ws:0"><em>outer</em><!--$--><em>inner</em><!--/$--></template><script>$weftSwap(0)</script>`,
    ])
    // Had the inner one still been pending, it would have its own segment, later.
    let (outer, resolveOuter) = deferred()
    let (inner, resolveInner) = deferred()
    let rendering = Html.render(
      <Weft.Suspense fallback={string("outer loading")}>
        <Waits promise=outer />
        <Weft.Suspense fallback={string("inner loading")}>
          <Waits promise=inner />
        </Weft.Suspense>
      </Weft.Suspense>,
    )
    let _ = await rendering->Html.shell
    let rest = chunks(rendering->Html.rest)
    resolveOuter("outer")
    await tick()
    await tick()
    resolveInner("inner")
    t
    ->expect((await rest)->Array.map(withoutRuntime))
    ->Expect.toEqual([
      `<template id="ws:0"><em>outer</em><!--$?--><template id="wb:1"></template>inner loading<!--/$--></template><script>$weftSwap(0)</script>`,
      `<template id="ws:1"><em>inner</em></template><script>$weftSwap(1)</script>`,
    ])
  })

  testAsync("fails a boundary whose content fails later, with a script", async t => {
    let (promise, resolve) = deferred()
    module FailsAfter = {
      @weft.component
      let make = (~promise: promise<string>) =>
        JsError.throwWithMessage(`failed after ${Hooks.use(promise)}`)
    }
    let rendering = Html.render(
      ~onError=_ => Some("d2"),
      <Weft.Suspense fallback={string("loading")}>
        <FailsAfter promise />
      </Weft.Suspense>,
    )
    let _ = await rendering->Html.shell
    let rest = chunks(rendering->Html.rest)
    resolve("waiting")
    t
    ->expect((await rest)->Array.map(withoutRuntime))
    ->Expect.toEqual([`<script>$weftFail(0,"d2","failed after waiting")</script>`])
  })

  testAsync("rejects the shell for an error outside every boundary, and ends the rest", async t => {
    let rendering = Html.render(
      ~onError=_ => None,
      <div>
        <Fails message="shell" />
      </div>,
    )
    t->expect(await rejection(() => rendering->Html.shell))->Expect.toEqual(Some("shell"))
    t->expect(await chunks(rendering->Html.rest))->Expect.toEqual([])
  })

  testAsync("stops when aborted: nothing more is written", async t => {
    let (promise, resolve) = deferred()
    let controller = makeController()
    let rendering = Html.render(
      <Weft.Suspense fallback={string("loading")}>
        <Waits promise />
      </Weft.Suspense>,
      ~signal=controller->signalOf,
    )
    let _ = await rendering->Html.shell
    let rest = chunks(rendering->Html.rest)
    controller->abort
    resolve("too late")
    t->expect(await rest)->Expect.toEqual([])
  })

  testAsync("renderToStream sends the shell, then the rest", async t => {
    let (promise, resolve) = deferred()
    let stream = Html.renderToStream(
      <div>
        <Weft.Suspense fallback={string("loading")}>
          <Waits promise />
        </Weft.Suspense>
      </div>,
    )
    let all = chunks(stream)
    await tick()
    resolve("done")
    t
    ->expect((await all)->Array.map(withoutRuntime))
    ->Expect.toEqual([
      `<div><!--$?--><template id="wb:0"></template>loading<!--/$--></div>`,
      `<template id="ws:0"><em>done</em></template><script>$weftSwap(0)</script>`,
    ])
  })
})

// The runtime, in jsdom

let setRetry: (Dom.element, int, unit => unit) => unit = %raw(`(container, index, retry) => {
  const markers = [...container.childNodes].filter(node => node.nodeType === 8 && node.data[0] === "$");
  markers[index].$weftRetry = retry;
}`)

describe("the runtime", () => {
  testAsync("swaps a segment in over the fallback, and tells hydration", async t => {
    let (promise, resolve) = deferred()
    let rendering = Html.render(
      <>
        <Weft.Suspense fallback={<i> {string("loading")} </i>}>
          <Waits promise />
        </Weft.Suspense>
        {string("after")}
      </>,
    )
    let container = page(await rendering->Html.shell)
    let retried = ref(false)
    setRetry(container, 0, () => retried := true)
    let rest = chunks(rendering->Html.rest)
    resolve("done")
    let segment = (await rest)->Array.join("")
    arrive(segment)
    run(segment)
    t->expect(markup(container))->Expect.toBe("<!--$--><em>done</em><!--/$-->after")
    t->expect(retried.contents)->Expect.toBe(true)
  })

  testAsync("swaps segments in whatever order they come, in a table too", async t => {
    let (first, resolveFirst) = deferred()
    let (second, resolveSecond) = deferred()
    module Row = {
      @weft.component
      let make = (~promise: promise<string>) =>
        <tr>
          <td> {string(Hooks.use(promise))} </td>
        </tr>
    }
    let rendering = Html.render(
      <table>
        <tbody>
          <Weft.Suspense
            fallback={<tr>
              <td> {string("1…")} </td>
            </tr>}
          >
            <Row promise=first />
          </Weft.Suspense>
          <Weft.Suspense
            fallback={<tr>
              <td> {string("2…")} </td>
            </tr>}
          >
            <Row promise=second />
          </Weft.Suspense>
        </tbody>
      </table>,
    )
    let container = page(await rendering->Html.shell)
    let rest = chunks(rendering->Html.rest)
    resolveSecond("two")
    await tick()
    resolveFirst("one")
    (await rest)->Array.forEach(
      segment => {
        arrive(segment)
        run(segment)
      },
    )
    t
    ->expect(markup(container))
    ->Expect.toBe(
      "<table><tbody><!--$--><tr><td>one</td></tr><!--/$--><!--$--><tr><td>two</td></tr><!--/$--></tbody></table>",
    )
  })

  testAsync("marks a boundary failed, keeping its fallback, and tells hydration", async t => {
    let (promise, resolve) = deferred()
    module FailsAfter = {
      @weft.component
      let make = (~promise: promise<string>) => JsError.throwWithMessage(Hooks.use(promise))
    }
    let rendering = Html.render(
      ~onError=_ => Some("d3"),
      <Weft.Suspense fallback={string("fallback")}>
        <FailsAfter promise />
      </Weft.Suspense>,
    )
    let container = page(await rendering->Html.shell)
    let retried = ref(false)
    setRetry(container, 0, () => retried := true)
    let rest = chunks(rendering->Html.rest)
    resolve("broke")
    let script = (await rest)->Array.join("")
    run(script)
    t
    ->expect(markup(container))
    ->Expect.toBe(`<!--$!--><template data-digest="d3" data-message="broke"></template>fallback<!--/$-->`)
    t->expect(retried.contents)->Expect.toBe(true)
  })
})

// The oracle: the HTML parses into the DOM a client render makes

module Echo = {
  /** A component that renders its children, with state, as an entrypoint might. */
  @weft.component
  let make = (~children: Jsx.element) => {
    let (label, _) = Hooks.useState(() => "echo")
    <span title=label> children </span>
  }
}

let texts = ["a", "b", "", "<&>", "\"q\"", " spaced "]

let rec randomTree = (random, ~depth): Jsx.element =>
  switch Random.intBelow(random, depth <= 0 ? 3 : 9) {
  | 0 | 1 => string(Random.pick(random, texts))
  | 2 => <input value={Random.pick(random, texts)} checked={Random.intBelow(random, 2) == 0} />
  | 3 => <Echo> {randomChildren(random, ~depth=depth - 1)} </Echo>
  | 4 => <> {randomChildren(random, ~depth=depth - 1)} </>
  | 5 => <textarea value={Random.pick(random, ["", "x", "\nnewline first", "a & b"])} />
  | 6 => themeProvider(Random.pick(random, texts), <Themed />)
  | _ =>
    let tag = Random.pick(random, ["div", "span", "b", "ul", "section"])
    let children = randomChildren(random, ~depth=depth - 1)
    let props: DomProps.props = {
      id: ?(Random.intBelow(random, 2) == 0 ? Some(Random.pick(random, texts)) : None),
      className: ?(Random.intBelow(random, 2) == 0 ? Some("c") : None),
      hidden: ?(Random.intBelow(random, 3) == 0 ? Some(Random.intBelow(random, 2) == 0) : None),
      style: ?(Random.intBelow(random, 3) == 0 ? Some(dict{"backgroundColor": "red"}) : None),
      children,
    }
    Weft.JsxCore.hostJsx(tag, props)
  }

and randomChildren = (random, ~depth) => {
  let children = Array.fromInitializer(~length=Random.intBelow(random, 4), _ =>
    randomTree(random, ~depth)
  )
  // As JSX writes a list of children: no keys needed.
  Weft.JsxCore.markStaticList(children)
  Jsx.array(children)
}

describe("the HTML, parsed", () => {
  testAsync("is the DOM a client render of the same tree makes, for random trees", async t => {
    for seed in 1 to 150 {
      let random = Random.make(Int.toFloat(seed))
      let tree = <div> {randomChildren(random, ~depth=4)} </div>
      let fromHtml = page(await html(tree))
      let fromClient = clientRender(tree)
      t
      ->expect((seed, structure(fromHtml)))
      ->Expect.toEqual((seed, structure(fromClient)))
    }
  })
})
