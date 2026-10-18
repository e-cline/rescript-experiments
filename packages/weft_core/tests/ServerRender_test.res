@@jsxConfig({version: 4, module_: "TestJsx"})

/***
What server renderers rely on: `ServerRender.run` (hooks fail with a message saying why, `use`
suspends, and nothing leaks into client renders) and `Entrypoint` marks.
*/

open Vitest

/** The message of the error `f` throws, or `None` if it doesn't throw. */
let errorOf = (f: unit => 'a): option<string> =>
  switch f() {
  | _ => None
  | exception JsExn(error) => JsExn.message(error)
  | exception _ => Some("(not a JS error)")
  }

let serverMessage = "WeftCore: this hook can't be used in a component rendered on the server. Only Hooks.use works there; a component with state or effects has to run in the browser (an entrypoint)."

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
    ->Expect.toEqual(
      Some("WeftCore: hooks can only be called while a function component is rendering"),
    )
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
