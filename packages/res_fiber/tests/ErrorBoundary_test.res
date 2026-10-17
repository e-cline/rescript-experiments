@@jsxConfig({version: 4, module_: "TestJsx"})

open Vitest

let fallback = (~error, ~reset as _) =>
  <p id="fallback"> {TestJsx.string(`caught: ${ErrorBoundary.message(error)}`)} </p>

/** Throws while rendering whenever `fail` is true. */
let failing = ref(false)

module Thrower = {
  @jsx.component
  let make = (~name: string) => {
    if failing.contents {
      JsError.throwWithMessage(`${name} failed`)
    }
    <span id=name> {TestJsx.string(name)} </span>
  }
}

let resetBoundary = ref(() => ())

let resettable = (~error, ~reset) => {
  resetBoundary := reset
  fallback(~error, ~reset)
}

describe("ErrorBoundary: errors while rendering", () => {
  beforeEach(() => failing := false)

  test("renders the fallback instead of the children, leaving the rest alone", t => {
    failing := true
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <div id="page">
        <ErrorBoundary fallback>
          <Thrower name="widget" />
        </ErrorBoundary>
        <span id="footer"> {TestJsx.string("footer")} </span>
      </div>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div id="page"><p id="fallback">caught: widget failed</p><span id="footer">footer</span></div>`)
  })

  test("replaces children that were on screen, and reset brings them back", t => {
    let renderer = TestRenderer.create()
    let view = (~title) =>
      <ErrorBoundary fallback=resettable>
        <div id="box" title>
          <Thrower name="widget" />
        </div>
      </ErrorBoundary>
    TestRenderer.render(renderer, view(~title="1"))
    failing := true
    TestRenderer.render(renderer, view(~title="2"))
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<p id="fallback">caught: widget failed</p>`)
    // Still showing the fallback while nothing changes.
    TestRenderer.render(renderer, view(~title="3"))
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<p id="fallback">caught: widget failed</p>`)
    failing := false
    TestRenderer.act(() => resetBoundary.contents())
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div id="box" title="3"><span id="widget">widget</span></div>`)
  })

  test("the nearest boundary catches", t => {
    failing := true
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ErrorBoundary fallback={(~error as _, ~reset as _) => TestJsx.string("outer")}>
        <ErrorBoundary fallback={(~error as _, ~reset as _) => TestJsx.string("inner")}>
          <Thrower name="widget" />
        </ErrorBoundary>
      </ErrorBoundary>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("inner")
  })

  test("an error in a fallback goes to the next boundary up", t => {
    failing := true
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ErrorBoundary fallback>
        <ErrorBoundary fallback={(~error as _, ~reset as _) => <Thrower name="fallback-widget" />}>
          <Thrower name="widget" />
        </ErrorBoundary>
      </ErrorBoundary>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<p id="fallback">caught: fallback-widget failed</p>`)
  })

  test("with no boundary, the error comes out of the render", t => {
    failing := true
    t
    ->expect(() => TestRenderer.render(TestRenderer.create(), <Thrower name="widget" />))
    ->Expect.toThrow(~message="widget failed")
  })

  test("context values provided below the boundary are unwound", t => {
    let theme = Context.make("default")
    module ThemeProvider = {
      let make = Context.provider(theme)
    }
    module Label = {
      @jsx.component
      let make = () => <i id="label"> {TestJsx.string(Hooks.useContext(theme))} </i>
    }
    failing := true
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <>
        <ErrorBoundary fallback>
          <ThemeProvider value="inner">
            <Thrower name="widget" />
          </ThemeProvider>
        </ErrorBoundary>
        <Label />
      </>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<p id="fallback">caught: widget failed</p><i id="label">default</i>`)
  })

  test("children's effects are cleaned up when the fallback replaces them", t => {
    let cleanedUp = ref(false)
    module WithEffect = {
      @jsx.component
      let make = () => {
        Hooks.useEffect0(() => Some(() => cleanedUp := true))
        <Thrower name="widget" />
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ErrorBoundary fallback>
        <WithEffect />
      </ErrorBoundary>,
    )
    failing := true
    TestRenderer.render(
      renderer,
      <ErrorBoundary fallback>
        <WithEffect />
      </ErrorBoundary>,
    )
    t->expect(cleanedUp.contents)->Expect.toBe(true)
  })

  test("catches errors in a transition's render", t => {
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ErrorBoundary fallback>
        <Thrower name="widget" />
      </ErrorBoundary>,
    )
    failing := true
    Transition.start(
      () =>
        TestRenderer.scheduleRender(
          renderer,
          <ErrorBoundary fallback>
            <Thrower name="widget" />
          </ErrorBoundary>,
        ),
    )
    TestScheduler.flushAll()
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<p id="fallback">caught: widget failed</p>`)
  })

  test("a ReScript exception's message is its name", t => {
    let renderer = TestRenderer.create()
    module Raises = {
      @jsx.component
      let make = () => throw(Not_found)
    }
    TestRenderer.render(
      renderer,
      <ErrorBoundary fallback>
        <Raises />
      </ErrorBoundary>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<p id="fallback">caught: Not_found</p>`)
  })
})

describe("ErrorBoundary: errors in effects", () => {
  beforeEach(() => failing := false)

  test("a layout effect's error shows the fallback", t => {
    module BadLayout = {
      @jsx.component
      let make = () => {
        Hooks.useLayoutEffect0(() => JsError.throwWithMessage("layout failed"))
        <span id="ok" />
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ErrorBoundary fallback>
        <BadLayout />
      </ErrorBoundary>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<p id="fallback">caught: layout failed</p>`)
  })

  test("a passive effect's error shows the fallback", t => {
    module BadEffect = {
      @jsx.component
      let make = () => {
        Hooks.useEffect0(() => JsError.throwWithMessage("effect failed"))
        <span id="ok" />
      }
    }
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ErrorBoundary fallback>
        <BadEffect />
      </ErrorBoundary>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<p id="fallback">caught: effect failed</p>`)
  })
})
