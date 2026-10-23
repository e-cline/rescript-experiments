@@jsxConfig({version: 4, module_: "TestJsx"})

/***
What server renderers rely on: `ServerRender.run` (hooks fail with a message saying why, `use`
suspends, and nothing leaks into client renders), `ServerRender.renderComponent` (client components
on the server: hooks work as on a first render that never commits) and `Entrypoint` marks.
*/

open Vitest

/** The message of the error `f` throws, or `None` if it doesn't throw. */
let errorOf = (f: unit => 'a): option<string> =>
  switch f() {
  | _ => None
  | exception JsExn(error) => JsExn.message(error)
  | exception _ => Some("(not a JS error)")
  }

let serverMessage = "Weft: this hook can't be used in a component rendered on the server. Only Hooks.use works there; a component with state or effects has to run in the browser (an entrypoint)."

module Stateful = {
  @jsx.component
  let make = () => {
    let (count, _) = Hooks.useState(() => 0)
    <b> {TestJsx.int(count)} </b>
  }
}

describe("ServerRender.run", () => {
  test("each hook that keeps state or runs effects fails with the server message", t => {
    let hooks: array<(string, unit => unit)> = [
      ("useState", () => Hooks.useState(() => 0)->ignore),
      ("useReducer", () => Hooks.useReducer((state, _: unit) => state, 0)->ignore),
      ("useRef", () => Hooks.useRef(0)->ignore),
      ("useMemo0", () => Hooks.useMemo0(() => 0)->ignore),
      ("useEffect0", () => Hooks.useEffect0(() => None)),
      ("useLayoutEffect0", () => Hooks.useLayoutEffect0(() => None)),
      ("useContext", () => Hooks.useContext(Context.make(0))->ignore),
      ("useTransition", () => Hooks.useTransition()->ignore),
      ("useDeferredValue", () => Hooks.useDeferredValue(0)->ignore),
      ("useId", () => Hooks.useId()->ignore),
    ]
    hooks->Array.forEach(
      ((name, call)) =>
        t
        ->expect((name, errorOf(() => ServerRender.run(call))))
        ->Expect.toEqual((name, Some(serverMessage))),
    )
  })

  test("outside it, the same hooks still say they need a component", t => {
    t
    ->expect(errorOf(() => Hooks.useState(() => 0)))
    ->Expect.toEqual(Some("Weft: hooks can only be called while a function component is rendering"))
  })

  test("Hooks.use returns a settled promise's value, and throws Suspended for a pending one", t => {
    let pending = Promise.make((_, _) => ())
    let suspended = switch ServerRender.run(() => Hooks.use(pending)) {
    | _ => false
    | exception SuspenseImpl.Suspended(_) => true
    }
    t->expect(suspended)->Expect.toBe(true)
  })

  testAsync("Hooks.use reads a promise that has settled, without suspending", async t => {
    let data = Promise.resolve("ready")
    // The first `use` starts tracking the promise, and suspends; once it has settled, `use` reads it.
    switch ServerRender.run(() => Hooks.use(data)) {
    | _ => ()
    | exception SuspenseImpl.Suspended(_) => ()
    }
    await data->Promise.thenResolve(_ => ())
    t->expect(ServerRender.run(() => Hooks.use(data)))->Expect.toBe("ready")
  })

  test("calls a component, and returns what it rendered", t => {
    module Greeting = {
      @jsx.component
      let make = (~name: string) => <p> {TestJsx.string(`Hello, ${name}`)} </p>
    }
    let element = ServerRender.run(() => Greeting.make({name: "server"}))
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, element)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<p>Hello, server</p>")
  })

  test("is only in effect during the call, however it ends", t => {
    t->expect(ServerRender.isRunning())->Expect.toBe(false)
    t->expect(ServerRender.run(() => ServerRender.isRunning()))->Expect.toBe(true)
    t->expect(ServerRender.isRunning())->Expect.toBe(false)
    let threw = switch ServerRender.run(() => JsError.throwWithMessage("failed")) {
    | _ => None
    | exception JsExn(error) => JsExn.message(error)
    }
    // The JS error itself comes out, not a wrapper.
    t->expect(threw)->Expect.toEqual(Some("failed"))
    t->expect(ServerRender.isRunning())->Expect.toBe(false)
    // A client render afterwards is unaffected.
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Stateful />)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<b>0</b>")
  })

  test("sets aside a client render it's called from, so hooks can't reach its component", t => {
    let insideServer = ref(None)
    module Host = {
      @jsx.component
      let make = () => {
        // A server render started while this component renders: its hooks must not land here.
        insideServer := Some(errorOf(() => ServerRender.run(() => Hooks.useState(() => 1))))
        let (count, _) = Hooks.useState(() => 0)
        <b> {TestJsx.int(count)} </b>
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Host />)
    t->expect(insideServer.contents)->Expect.toEqual(Some(Some(serverMessage)))
    // And this component's own hooks still work, in order, on the next render too.
    TestRenderer.render(renderer, <Host />)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<b>0</b>")
  })
})

/** What `component` rendered with `props` through `renderComponent`, as the TestRenderer prints it. */
let rendered = (~contexts=[], component, props) => {
  let element = ServerRender.renderComponent(component, props, {contexts: contexts})
  let renderer = TestRenderer.create()
  TestRenderer.render(renderer, element)
  TestRenderer.toString(renderer)
}

let theme = Context.make("plain")

/** Store reads the reconciler would check before committing: none may be left behind. */
let storeReads = () => Array.length(HookImpl.storeChecks)

describe("ServerRender.renderComponent", () => {
  test("gives each hook its initial value, as a first render does", t => {
    module Everything = {
      @jsx.component
      let make = (~start: int) => {
        let (count, _) = Hooks.useState(() => start)
        let (total, _) = Hooks.useReducer((total, n) => total + n, 10)
        let ref = Hooks.useRef("ref")
        let doubled = Hooks.useMemo1(() => count * 2, [count])
        let callback = Hooks.useCallback0(() => "callback")
        let (isPending, _) = Hooks.useTransition()
        let deferred = Hooks.useDeferredValue("deferred")
        let (mapped, _) = Hooks.useReducerWithMapState((state, _: unit) => state, 2, n => n * 3)
        <p>
          {TestJsx.string(
            [
              Int.toString(count),
              Int.toString(total),
              ref.current,
              Int.toString(doubled),
              callback(),
              isPending ? "pending" : "idle",
              deferred,
              Int.toString(mapped),
            ]->Array.join(" "),
          )}
        </p>
      }
    }
    t
    ->expect(rendered(Everything.make, {start: 4}))
    ->Expect.toBe("<p>4 10 ref 8 callback idle deferred 6</p>")
  })

  test("renders again when the component sets its own state while rendering", t => {
    let renders = ref(0)
    module Derived = {
      @jsx.component
      let make = () => {
        renders := renders.contents + 1
        let (count, setCount) = Hooks.useState(() => 0)
        if count < 3 {
          setCount(count => count + 1)
        }
        <b> {TestJsx.int(count)} </b>
      }
    }
    t->expect(rendered(Derived.make, {}))->Expect.toBe("<b>3</b>")
    t->expect(renders.contents)->Expect.toBe(4)
  })

  test("reads contexts from its options, innermost last, and puts them back after", t => {
    module Themed = {
      @jsx.component
      let make = () => <i> {TestJsx.string(Hooks.useContext(theme))} </i>
    }
    t->expect(rendered(Themed.make, {}))->Expect.toBe("<i>plain</i>")
    t
    ->expect(
      rendered(
        ~contexts=[
          ServerRender.contextValue(theme, "outer"),
          ServerRender.contextValue(theme, "dark"),
        ],
        Themed.make,
        {},
      ),
    )
    ->Expect.toBe("<i>dark</i>")
    // Back to the default for the next call, and for client renders.
    t->expect(rendered(Themed.make, {}))->Expect.toBe("<i>plain</i>")
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Themed />)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<i>plain</i>")
  })

  testAsync("never runs effects, and drops an update made later", async t => {
    let ran = []
    let setLater = ref(None)
    module Effects = {
      @jsx.component
      let make = () => {
        let (count, setCount) = Hooks.useState(() => 0)
        setLater := Some(setCount)
        Hooks.useEffect0(
          () => {
            ran->Array.push("effect")
            None
          },
        )
        Hooks.useLayoutEffect0(
          () => {
            ran->Array.push("layout")
            None
          },
        )
        <b> {TestJsx.int(count)} </b>
      }
    }
    t->expect(rendered(Effects.make, {}))->Expect.toBe("<b>0</b>")
    // An update from a handler kept somewhere: it reaches no root, and nothing renders.
    setLater.contents->Option.forEach(set => set(count => count + 1))
    TestScheduler.flushAll()
    await Promise.make((resolve, _) => setTimeout(() => resolve(), 5)->ignore)
    t->expect(ran)->Expect.toEqual([])
  })

  test("reads useSyncExternalStore's server snapshot, and fails without one", t => {
    let subscribe = _ => () => ()
    module Store = {
      @jsx.component
      let make = (~withServer: bool) => {
        let value = withServer
          ? Hooks.useSyncExternalStore(
              ~subscribe,
              ~getSnapshot=() => "browser",
              ~getServerSnapshot=() => "server",
            )
          : Hooks.useSyncExternalStore(~subscribe, ~getSnapshot=() => "browser")
        <s> {TestJsx.string(value)} </s>
      }
    }
    let before = storeReads()
    let element = ServerRender.renderComponent(Store.make, {withServer: true}, {contexts: []})
    // The reads the reconciler would check before a commit aren't left behind (checked before
    // anything renders, since a client render clears them too).
    t->expect(storeReads())->Expect.toBe(before)
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, element)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<s>server</s>")
    t
    ->expect(errorOf(() => rendered(Store.make, {withServer: false})))
    ->Expect.toEqual(
      Some(
        "Weft: useSyncExternalStore needs a ~getServerSnapshot to render on the server (the store is the browser's): the snapshot the HTML should show",
      ),
    )
    t->expect(storeReads())->Expect.toBe(before)
  })

  testAsync("throws Suspended for a pending promise, and renders once it has settled", async t => {
    let (promise, resolve) = {
      let resolve = ref(_ => ())
      let promise = Promise.make((done, _) => resolve := done)
      (promise, resolve)
    }
    module Waits = {
      @jsx.component
      let make = (~promise: promise<string>) => {
        let (prefix, _) = Hooks.useState(() => "got ")
        <u> {TestJsx.string(prefix ++ Hooks.use(promise))} </u>
      }
    }
    let suspendedOn = switch ServerRender.renderComponent(
      Waits.make,
      {promise: promise},
      {contexts: []},
    ) {
    | _ => None
    | exception error => ServerRender.suspendedOn(error)
    }
    t->expect(Option.isSome(suspendedOn))->Expect.toBe(true)
    // Nothing of the call is left: hooks outside a component say so.
    t
    ->expect(errorOf(() => Hooks.useState(() => 0)))
    ->Expect.toEqual(Some("Weft: hooks can only be called while a function component is rendering"))
    resolve.contents("there")
    await promise->Promise.thenResolve(_ => ())
    t->expect(rendered(Waits.make, {promise: promise}))->Expect.toBe("<u>got there</u>")
  })

  test("rethrows a component's JS error as itself, and is only in effect during the call", t => {
    module Fails = {
      @jsx.component
      let make = () => {
        let (_, _) = Hooks.useState(() => 0)
        JsError.throwWithMessage("failed")
      }
    }
    t->expect(errorOf(() => rendered(Fails.make, {})))->Expect.toEqual(Some("failed"))
    t->expect(ServerRender.isRenderingComponent())->Expect.toBe(false)
    module Inside = {
      @jsx.component
      let make = () => <b> {TestJsx.string(ServerRender.isRenderingComponent() ? "yes" : "no")} </b>
    }
    t->expect(rendered(Inside.make, {}))->Expect.toBe("<b>yes</b>")
    t->expect(ServerRender.isRenderingComponent())->Expect.toBe(false)
  })

  test("sets aside a client render it's called from, which carries on as before", t => {
    module Stateful = {
      @jsx.component
      let make = (~label: string) => {
        let (value, _) = Hooks.useState(() => label)
        <i> {TestJsx.string(value)} </i>
      }
    }
    let inner = ref(TestJsx.null)
    module Host = {
      @jsx.component
      let make = () => {
        let (count, _) = Hooks.useState(() => 0)
        inner := ServerRender.renderComponent(Stateful.make, {label: "inner"}, {contexts: []})
        let (other, _) = Hooks.useState(() => "host")
        <b> {TestJsx.string(`${Int.toString(count)} ${other}`)} </b>
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Host />)
    let innerRenderer = TestRenderer.create()
    TestRenderer.render(innerRenderer, inner.contents)
    t->expect(TestRenderer.toString(innerRenderer))->Expect.toBe("<i>inner</i>")
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<b>0 host</b>")
    TestRenderer.render(renderer, <Host />)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<b>0 host</b>")
  })

  test(
    "sets aside a server component's run too: inside one, hooks work, and fail again after",
    t => {
      module Stateful = {
        @jsx.component
        let make = () => {
          let (value, _) = Hooks.useState(() => "client")
          <i> {TestJsx.string(value)} </i>
        }
      }
      let result = ServerRender.run(
        () => {
          let inner = rendered(Stateful.make, {})
          (inner, ServerRender.isRunning(), errorOf(() => Hooks.useState(() => 0)))
        },
      )
      t->expect(result)->Expect.toEqual(("<i>client</i>", true, Some(serverMessage)))
    },
  )
})

describe("Entrypoint", () => {
  module Marked = {
    @jsx.component
    let make = (~label: string) => <button> {TestJsx.string(label)} </button>
    let () = Entrypoint.mark(make, "@e-cline/example/src/Marked.res#")
  }
  module Unmarked = {
    @jsx.component
    let make = (~label: string) => <button> {TestJsx.string(label)} </button>
  }

  test("idOf gives a marked component's id, and None for any other", t => {
    t
    ->expect(Entrypoint.idOf(Marked.make))
    ->Expect.toEqual(Some("@e-cline/example/src/Marked.res#"))
    t->expect(Entrypoint.idOf(Unmarked.make))->Expect.toEqual(None)
  })

  test("a marked component renders as any other", t => {
    let render = element => {
      let renderer = TestRenderer.create()
      TestRenderer.render(renderer, element)
      TestRenderer.toString(renderer)
    }
    t->expect(render(<Marked label="Go" />))->Expect.toBe(render(<Unmarked label="Go" />))
  })
})
