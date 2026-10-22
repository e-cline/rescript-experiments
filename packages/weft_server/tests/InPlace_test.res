@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
Refetching: a payload rendered over the one on screen is patched in, not remounted. Each test
renders tree A through the server and client, bumps the entrypoints' counters, then renders tree B
(in a transition, as a refetch does) and checks the state, the host nodes and the operations the
TestRenderer logged.
*/

open Vitest
open Support

/** `tree` through the server and `client`, rendered into a new TestRenderer. */
let mount = async (~client, tree) => {
  let element = await roundTrip(~client, tree)
  let renderer = TestRenderer.create()
  TestRenderer.render(renderer, element)
  await settle()
  renderer
}

/** `tree` through the server and `client`, rendered over what `renderer` shows, in a transition. */
let refetch = async (~client, renderer, tree) => {
  let element = await roundTrip(~client, tree)
  TestRenderer.clearOps(renderer)
  WeftCore.Transition.start(() => TestRenderer.scheduleRender(renderer, element))
  await settle()
}

let ops = renderer => TestRenderer.ops(renderer)
let opsLike = (renderer, prefix) => ops(renderer)->Array.filter(op => op->String.startsWith(prefix))
let uid = (renderer, id) => TestRenderer.findById(renderer, id)->Option.map(TestRenderer.uid)
let shows = TestRenderer.toString

describe("refetching the same tree", () => {
  testAsync("changes nothing on the host, and keeps every entrypoint's state", async t => {
    resetCounts()
    let client = makeClient()
    let tree =
      <section id="page">
        <Counter label="a" />
        <Wrap id="w">
          <Counter label="b">
            <i id="child"> {text("child")} </i>
          </Counter>
        </Wrap>
      </section>
    let renderer = await mount(~client, tree)
    bump("a")
    bump("b")
    let before = shows(renderer)
    let rendersBefore = (rendersOf("a"), rendersOf("b"))
    await refetch(~client, renderer, tree)
    t->expect(shows(renderer))->Expect.toBe(before)
    t->expect(ops(renderer))->Expect.toEqual([])
    // Today, the entrypoints render again, since their decoded props are new objects (see the plan's
    // risks); what they render is diffed, so nothing on screen changes.
    let (a, b) = rendersBefore
    t->expect((rendersOf("a"), rendersOf("b")))->Expect.toEqual((a + 1, b + 1))
  })
})

describe("refetching with new props", () => {
  testAsync(
    "an entrypoint renders with them and keeps its state; only what changed is updated",
    async t => {
      resetCounts()
      let client = makeClient()
      let renderer = await mount(
        ~client,
        <div>
          <Counter label="a" note="old" />
        </div>,
      )
      bump("a")
      let node = uid(renderer, "a")
      await refetch(
        ~client,
        renderer,
        <div>
          <Counter label="a" note="new" />
        </div>,
      )
      t->expect(shows(renderer))->Expect.toBe(`<div><b id="a" title="new">a:1</b></div>`)
      t->expect(uid(renderer, "a"))->Expect.toEqual(node)
      t->expect(ops(renderer))->Expect.toEqual(["update b#a {title}"])
    },
  )

  testAsync("new element children are patched in, under kept state", async t => {
    resetCounts()
    let client = makeClient()
    let renderer = await mount(
      ~client,
      <Counter label="a">
        <i id="c"> {text("before")} </i>
      </Counter>,
    )
    bump("a")
    await refetch(
      ~client,
      renderer,
      <Counter label="a">
        <i id="c"> {text("after")} </i>
      </Counter>,
    )
    t->expect(shows(renderer))->Expect.toBe(`<b id="a">a:1<i id="c">after</i></b>`)
    t->expect(ops(renderer))->Expect.toEqual([`text "before" -> "after"`])
  })

  testAsync("a new promise prop is read in place", async t => {
    let client = makeClient()
    let renderer = await mount(~client, <Reader id="r" promise={Promise.resolve("first")} />)
    let node = uid(renderer, "r")
    await refetch(~client, renderer, <Reader id="r" promise={Promise.resolve("second")} />)
    t->expect(shows(renderer))->Expect.toBe(`<u id="r">second</u>`)
    t->expect(uid(renderer, "r"))->Expect.toEqual(node)
  })
})

describe("refetching with a different structure", () => {
  testAsync(
    "output from a different server component, the same on the host, isn't remounted",
    async t => {
      resetCounts()
      let client = makeClient()
      let renderer = await mount(
        ~client,
        <Wrap id="w">
          <Counter label="a" />
        </Wrap>,
      )
      bump("a")
      await refetch(
        ~client,
        renderer,
        <WrapAgain id="w">
          <Counter label="a" />
        </WrapAgain>,
      )
      t->expect(shows(renderer))->Expect.toBe(`<div id="w"><b id="a">a:1</b></div>`)
      t->expect(ops(renderer))->Expect.toEqual([])
    },
  )

  testAsync("a keyed list of entrypoints moves, inserts and removes, keeping the rest", async t => {
    resetCounts()
    let client = makeClient()
    let list = labels =>
      <ul> {TestJsx.array(labels->Array.map(label => <Counter key=label label />))} </ul>
    let renderer = await mount(~client, list(["a", "b", "c"]))
    bump("a")
    bump("c")
    let (a, c) = (uid(renderer, "a"), uid(renderer, "c"))
    await refetch(~client, renderer, list(["c", "a", "d"]))
    t
    ->expect(shows(renderer))
    ->Expect.toBe(`<ul><b id="c">c:1</b><b id="a">a:1</b><b id="d">d:0</b></ul>`)
    t->expect((uid(renderer, "a"), uid(renderer, "c")))->Expect.toEqual((a, c))
    t->expect(opsLike(renderer, "create b#"))->Expect.toEqual(["create b#d"])
    t->expect(opsLike(renderer, "remove"))->Expect.toEqual(["remove b#b"])
  })

  testAsync("a different entrypoint, key or host tag in the same place remounts", async t => {
    resetCounts()
    let client = makeClient()
    // Another entrypoint
    let renderer = await mount(
      ~client,
      <div>
        <Counter label="x" />
      </div>,
    )
    bump("x")
    await refetch(
      ~client,
      renderer,
      <div>
        <Inner label="x" />
      </div>,
    )
    t->expect(shows(renderer))->Expect.toBe(`<div><s id="x">x</s></div>`)
    // Another key
    let renderer = await mount(
      ~client,
      <div>
        <Counter key="1" label="y" />
      </div>,
    )
    bump("y")
    await refetch(
      ~client,
      renderer,
      <div>
        <Counter key="2" label="y" />
      </div>,
    )
    t->expect(shows(renderer))->Expect.toBe(`<div><b id="y">y:0</b></div>`)
    // Another host tag around it
    let renderer = await mount(
      ~client,
      <div>
        <Counter label="z" />
      </div>,
    )
    bump("z")
    await refetch(
      ~client,
      renderer,
      <p>
        <Counter label="z" />
      </p>,
    )
    t->expect(shows(renderer))->Expect.toBe(`<p><b id="z">z:0</b></p>`)
  })
})

describe("refetching over placeholders", () => {
  testAsync(
    "content that streamed in as a placeholder, and arrives complete next time, keeps its state",
    async t => {
      resetCounts()
      let client = makeClient()
      let ready = Deferred.make()
      let renderer = await mount(
        ~client,
        <WeftCore.Suspense fallback=loading>
          <Async ready=ready.promise>
            <Counter label="a" />
          </Async>
        </WeftCore.Suspense>,
      )
      t->expect(shows(renderer))->Expect.toBe(`<i id="loading">loading</i>`)
      ready.resolve()
      await settle()
      bump("a")
      await refetch(
        ~client,
        renderer,
        <WeftCore.Suspense fallback=loading>
          <Counter label="a" />
        </WeftCore.Suspense>,
      )
      t->expect(shows(renderer))->Expect.toBe(`<b id="a">a:1</b>`)
      t->expect(opsLike(renderer, "create"))->Expect.toEqual([])
    },
  )

  testAsync("and the other way round: complete first, a placeholder next time", async t => {
    resetCounts()
    let client = makeClient()
    let renderer = await mount(
      ~client,
      <WeftCore.Suspense fallback=loading>
        <Counter label="a" />
      </WeftCore.Suspense>,
    )
    bump("a")
    let ready = Deferred.make()
    await refetch(
      ~client,
      renderer,
      <WeftCore.Suspense fallback=loading>
        <Async ready=ready.promise>
          <Counter label="a" note="later" />
        </Async>
      </WeftCore.Suspense>,
    )
    // A boundary that's showing its content keeps showing it during the transition...
    t->expect(shows(renderer))->Expect.toBe(`<b id="a">a:1</b>`)
    ready.resolve()
    await settle()
    // ...until the new content is ready, and then it's patched in.
    t->expect(shows(renderer))->Expect.toBe(`<b id="a" title="later">a:1</b>`)
    t->expect(opsLike(renderer, "create"))->Expect.toEqual([])
  })

  testAsync("a payload that has fully arrived renders without suspending at all", async t => {
    resetCounts()
    let client = makeClient()
    let tree =
      <WeftCore.Suspense fallback=loading>
        <Async ready={Promise.resolve()}>
          <Counter label="a" />
        </Async>
      </WeftCore.Suspense>
    let pipe = Testing.pipe(Render.toStream(tree))
    let element = client->Decoder.fromStream(Testing.stream(pipe))
    await Testing.finished(pipe)
    await Testing.tick()
    let renderer = TestRenderer.create()
    // Rendered urgently: a suspension would show the fallback.
    TestRenderer.render(renderer, await element)
    t->expect(shows(renderer))->Expect.toBe(`<b id="a">a:0</b>`)
    t->expect(ops(renderer)->Array.some(op => op->String.includes("loading")))->Expect.toBe(false)
  })

  testAsync(
    "a boundary that's new in the refetch shows its fallback until its content is ready",
    async t => {
      resetCounts()
      let client = makeClient()
      let renderer = await mount(
        ~client,
        <div>
          <Counter label="a" />
        </div>,
      )
      bump("a")
      let ready = Deferred.make()
      await refetch(
        ~client,
        renderer,
        <div>
          <Counter label="a" />
          <WeftCore.Suspense fallback=loading>
            <Async ready=ready.promise>
              <b id="new" />
            </Async>
          </WeftCore.Suspense>
        </div>,
      )
      t
      ->expect(shows(renderer))
      ->Expect.toBe(`<div><b id="a">a:1</b><i id="loading">loading</i></div>`)
      ready.resolve()
      await settle()
      t->expect(shows(renderer))->Expect.toBe(`<div><b id="a">a:1</b><b id="new"></b></div>`)
    },
  )

  testAsync(
    "an entrypoint whose module hasn't loaded keeps the old screen until it has",
    async t => {
      resetCounts()
      let modules = makeModules()
      let client = makeClient(~modules)
      let renderer = await mount(
        ~client,
        <div>
          <Counter label="a" />
        </div>,
      )
      bump("a")
      modules->Testing.hold
      let done = refetch(
        ~client,
        renderer,
        <div>
          <Counter label="a" />
          <Inner label="i" />
        </div>,
      )
      await settle()
      t->expect(shows(renderer))->Expect.toBe(`<div><b id="a">a:1</b></div>`)
      modules->Testing.release
      await done
      t->expect(shows(renderer))->Expect.toBe(`<div><b id="a">a:1</b><s id="i">i</s></div>`)
    },
  )
})

describe("refetching, with errors", () => {
  testAsync(
    "an error inside a boundary shows there, and everything else keeps its state",
    async t => {
      resetCounts()
      let client = makeClient()
      let tree = content =>
        <div>
          <Counter label="a" />
          <Guard>
            <WeftCore.Suspense fallback=loading> content </WeftCore.Suspense>
          </Guard>
        </div>
      let renderer = await mount(~client, tree(<b id="fine" />))
      bump("a")
      let render = Render.toStream(tree(<Fails message="broken" />), ~onError=_ => None)
      let element = await client->Decoder.fromStream(Testing.stream(Testing.pipe(render)))
      WeftCore.Transition.start(() => TestRenderer.scheduleRender(renderer, element))
      await settle()
      t
      ->expect(shows(renderer))
      ->Expect.toBe(`<div><b id="a">a:1</b><p id="error">broken</p></div>`)
    },
  )

  testAsync("a refetch whose root fails rejects, and leaves the screen as it was", async t => {
    resetCounts()
    let client = makeClient()
    let renderer = await mount(
      ~client,
      <div>
        <Counter label="a" />
      </div>,
    )
    bump("a")
    let render = Render.toStream(
      <div>
        <Fails message="no page" />
      </div>,
      ~onError=_ => None,
    )
    let failed = switch await client->Decoder.fromStream(Testing.stream(Testing.pipe(render))) {
    | _ => None
    | exception JsExn(error) => JsExn.message(error)
    }
    t->expect(failed)->Expect.toEqual(Some("no page"))
    t->expect(shows(renderer))->Expect.toBe(`<div><b id="a">a:1</b></div>`)
  })
})

describe("refetching, in order", () => {
  /** A client whose fetches render `pages` on the server, delivered when the test says. */
  let fetching = pages => {
    let pipes = Dict.make()
    let fetch = (url, ~signal) => {
      let page = pages->Dict.getUnsafe(url)
      let pipe = Testing.pipe(Render.toStream(page(), ~signal), ~delivery=Manual)
      pipes->Dict.set(url, pipe)
      Promise.resolve(Testing.stream(pipe))
    }
    (Decoder.make(~loadModule=Testing.loadModule(makeModules()), ~fetch), pipes)
  }

  testAsync("only the latest of two fetches is returned, and the older is cancelled", async t => {
    let data = Deferred.make()
    let calls = ref(0)
    module Counted = {
      @jsx.component
      let make = (~promise) => {
        calls := calls.contents + 1
        text(WeftCore.Hooks.use(promise))
      }
    }
    let (client, pipes) = fetching(
      dict{
        "/old": () =>
          <div>
            <WeftCore.Suspense fallback=loading>
              <Counted promise=data.promise />
            </WeftCore.Suspense>
          </div>,
        "/new": () => <p> {text("new")} </p>,
      },
    )
    let latest = Decoder.Latest.make()
    let old = latest->Decoder.Latest.fetchElement(client, "/old")
    await Testing.tick()
    let new = latest->Decoder.Latest.fetchElement(client, "/new")
    await settle()
    pipes->Dict.getUnsafe("/new")->Testing.deliverAll
    let newElement = await new
    t->expect(newElement->Option.map(renderDirectly))->Expect.toEqual(Some("<p>new</p>"))
    // The older one comes to nothing, and its server render stopped: nothing is called again.
    t->expect(await old)->Expect.toEqual(None)
    data.resolve("too late")
    await settle()
    t->expect(calls.contents)->Expect.toBe(1)
  })

  testAsync("two separate sequences don't interfere", async t => {
    let (client, pipes) = fetching(dict{"/one": () => text("one"), "/two": () => text("two")})
    let (first, second) = (Decoder.Latest.make(), Decoder.Latest.make())
    let one = first->Decoder.Latest.fetchElement(client, "/one")
    let two = second->Decoder.Latest.fetchElement(client, "/two")
    await settle()
    pipes->Dict.valuesToArray->Array.forEach(Testing.deliverAll)
    t->expect((await one)->Option.map(renderDirectly))->Expect.toEqual(Some("one"))
    t->expect((await two)->Option.map(renderDirectly))->Expect.toEqual(Some("two"))
  })
})

type record = {name: string, count: int, tags: array<string>}
type variant = Plain | WithPayload(int, string) | WithRecord({inner: option<int>})

/** `value`, sent from the server to a `Probe` entrypoint, as the entrypoint received it. */
let roundTripValue: 'value. 'value => promise<'value> = async value => {
  let _ = await renderRoundTrip(<Probe name="value" value />)
  Values.fromUnknown(received->Dict.getUnsafe("value"))
}

describe("values sent to an entrypoint", () => {
  testAsync(
    "records, variants, options, dicts, tuples and arrays arrive as they were sent",
    async t => {
      let value = (
        {name: "n", count: 3, tags: ["a", "$b"]},
        [Plain, WithPayload(1, "x"), WithRecord({inner: Some(2)}), WithRecord({inner: None})],
        (Some(Some(1)), Some(None), None),
        dict{"k": [1.5, -2.0]},
        [Some("x"), None],
      )
      t->expect(await roundTripValue(value))->Expect.toEqual(value)
    },
  )

  testAsync("so do bigints, dates and numbers JSON can't hold", async t => {
    let date = Date.fromString("2026-01-02T03:04:05.000Z")
    let (big, when_, nan, inf, negZero) = await roundTripValue((
      123456789012345678901234567890n,
      date,
      Float.Constants.nan,
      Float.Constants.negativeInfinity,
      -0.0,
    ))
    t->expect(big)->Expect.toBe(123456789012345678901234567890n)
    t->expect(Date.getTime(when_))->Expect.toBe(Date.getTime(date))
    t->expect(Float.isNaN(nan))->Expect.toBe(true)
    t->expect(inf)->Expect.toBe(Float.Constants.negativeInfinity)
    t->expect(Object.is(negZero, -0.0))->Expect.toBe(true)
  })

  testAsync("so do elements, rendered on the server", async t => {
    let element = await roundTripValue(<Wrap id="w"> {text("x")} </Wrap>)
    t->expect(renderDirectly(element))->Expect.toBe(`<div id="w">x</div>`)
  })
})
