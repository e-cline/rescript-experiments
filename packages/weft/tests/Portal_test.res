@@jsxConfig({version: 4, module_: "TestJsx"})

open Vitest

let setup = () => {
  let renderer = TestRenderer.create()
  let modal = TestRenderer.createTarget(renderer, "modal")
  (renderer, modal)
}

describe("Portals", () => {
  test("render their children into the target, not the parent", t => {
    let (renderer, modal) = setup()
    TestRenderer.render(
      renderer,
      <div id="app">
        {TestRenderer.portal(modal, <b id="dialog"> {TestJsx.string("hi")} </b>)}
        <i id="after" />
      </div>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div id="app"><i id="after"></i></div>`)
    t->expect(TestRenderer.targetToString(modal))->Expect.toBe(`<b id="dialog">hi</b>`)
    t
    ->expect(TestRenderer.ops(renderer)->Array.includes("append b#dialog to modal"))
    ->Expect.toBe(true)
  })

  test("update in place and leave with their owner", t => {
    let (renderer, modal) = setup()
    let view = (~text, ~open_) =>
      <div id="app">
        {open_
          ? TestRenderer.portal(modal, <b id="dialog"> {TestJsx.string(text)} </b>)
          : TestJsx.null}
      </div>
    TestRenderer.render(renderer, view(~text="one", ~open_=true))
    TestRenderer.clearOps(renderer)
    TestRenderer.render(renderer, view(~text="two", ~open_=true))
    t->expect(TestRenderer.ops(renderer))->Expect.toEqual([`text "one" -> "two"`])
    TestRenderer.clearOps(renderer)
    TestRenderer.render(renderer, view(~text="two", ~open_=false))
    t->expect(TestRenderer.ops(renderer))->Expect.toEqual(["remove b#dialog"])
    t->expect(TestRenderer.targetToString(modal))->Expect.toBe("")
  })

  test("nodes inserted next to a portal skip its children", t => {
    let (renderer, modal) = setup()
    let view = (~first) =>
      <div id="app">
        {first ? <i id="first" /> : TestJsx.null}
        {TestRenderer.portal(modal, <b id="dialog" />)}
        <i id="last" />
      </div>
    TestRenderer.render(renderer, view(~first=false))
    TestRenderer.clearOps(renderer)
    TestRenderer.render(renderer, view(~first=true))
    t
    ->expect(TestRenderer.ops(renderer))
    ->Expect.toEqual(["create i#first", "insert i#first before i#last"])
  })

  test("context and effects work across them", t => {
    let theme = Context.make("light")
    module ThemeProvider = {
      let make = Context.provider(theme)
    }
    let mounted = ref(0)
    module Label = {
      @weft.component
      let make = () => {
        Hooks.useEffect0(
          () => {
            mounted := mounted.contents + 1
            Some(() => mounted := mounted.contents - 1)
          },
        )
        <i id="label"> {TestJsx.string(Hooks.useContext(theme))} </i>
      }
    }
    let (renderer, modal) = setup()
    TestRenderer.render(
      renderer,
      <ThemeProvider value="dark"> {TestRenderer.portal(modal, <Label />)} </ThemeProvider>,
    )
    t->expect(TestRenderer.targetToString(modal))->Expect.toBe(`<i id="label">dark</i>`)
    t->expect(mounted.contents)->Expect.toBe(1)
    TestRenderer.unmount(renderer)
    t->expect((TestRenderer.targetToString(modal), mounted.contents))->Expect.toEqual(("", 0))
  })

  test("an error in a portal reaches the boundary around it", t => {
    module Throws = {
      @weft.component
      let make = () => JsError.throwWithMessage("portal failed")
    }
    let (renderer, modal) = setup()
    TestRenderer.render(
      renderer,
      <ErrorBoundary
        fallback={(~error, ~reset as _) => TestJsx.string(ErrorBoundary.message(error))}
      >
        {TestRenderer.portal(modal, <Throws />)}
      </ErrorBoundary>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("portal failed")
  })
})
