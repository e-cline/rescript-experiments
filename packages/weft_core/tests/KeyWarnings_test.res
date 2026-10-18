@@jsxConfig({version: 4, module_: "TestJsx"})

/***
The development-build key warnings: two children with the same key in any list, and children
without a key in a `Jsx.array` list of more than one. Tests run as a development build.
*/

open Vitest

/** The warnings `f` causes, captured instead of logged. */
let warningsDuring = (f: unit => unit): array<string> => {
  let original = KeyWarnings.warn.contents
  let warnings = []
  KeyWarnings.warn := (message => warnings->Array.push(message))
  try f() catch {
  | error =>
    KeyWarnings.warn := original
    throw(error)
  }
  KeyWarnings.warn := original
  warnings
}

let renderWarnings = (element: TestJsx.element): array<string> =>
  warningsDuring(() => TestRenderer.render(TestRenderer.create(), element))

/** A `<ul>` of `<li>`s from a `Jsx.array` list: `Some(key)` with that key and id, `None` without. */
module Items = {
  @jsx.component
  let make = (~keys: array<option<string>>) =>
    <ul id="list">
      {keys
      ->Array.map(key =>
        switch key {
        | Some(key) => <li key id=key />
        | None => <li />
        }
      )
      ->TestJsx.array}
    </ul>
}

module Item = {
  @jsx.component
  let make = () => <li />
}

describe("KeyWarnings: duplicate keys", () => {
  test("warns about two children with the same key, naming it", t => {
    t
    ->expect(renderWarnings(<Items keys=[Some("a"), Some("b"), Some("a")] />))
    ->Expect.toEqual([
      `WeftCore: Encountered two children with the same key, "a", in <ul> rendered by KeyWarnings_test.Items. Keys should be unique so that children keep their identity across updates; with duplicates, children may be duplicated or omitted.`,
    ])
  })

  test("warns once per list per render, however many keys repeat", t => {
    let renderer = TestRenderer.create()
    let keys = [Some("a"), Some("a"), Some("b"), Some("b"), Some("a")]
    t
    ->expect(warningsDuring(() => TestRenderer.render(renderer, <Items keys />)))
    ->Expect.Array.toHaveLength(1)
    t
    ->expect(warningsDuring(() => TestRenderer.render(renderer, <Items keys />)))
    ->Expect.Array.toHaveLength(1)
  })

  test("warns about duplicates among static children too", t => {
    let warnings = renderWarnings(
      <ul id="static">
        <li key="x" />
        <li key="x" />
      </ul>,
    )
    t->expect(warnings)->Expect.Array.toHaveLength(1)
    t->expect(warnings->Array.getUnsafe(0))->Expect.String.toContain(`same key, "x", in <ul>`)
  })

  test("doesn't warn about distinct keys, on mount or when they move", t => {
    let renderer = TestRenderer.create()
    let warnings = warningsDuring(
      () => {
        TestRenderer.render(renderer, <Items keys=[Some("a"), Some("b"), Some("c")] />)
        TestRenderer.render(renderer, <Items keys=[Some("c"), Some("a"), Some("d")] />)
      },
    )
    t->expect(warnings)->Expect.toEqual([])
  })
})

describe("KeyWarnings: missing keys", () => {
  test("warns about children without a key in a Jsx.array list", t => {
    t
    ->expect(renderWarnings(<Items keys=[Some("a"), None, None] />))
    ->Expect.toEqual([
      `WeftCore: Each child in a list should have a unique "key" prop. The list in <ul> rendered by KeyWarnings_test.Items has children without one.`,
    ])
  })

  test("warns on updates as well as on mount", t => {
    let renderer = TestRenderer.create()
    let warnings = warningsDuring(
      () => {
        TestRenderer.render(renderer, <Items keys=[Some("a"), Some("b")] />)
        TestRenderer.render(renderer, <Items keys=[Some("a"), None] />)
      },
    )
    t->expect(warnings)->Expect.Array.toHaveLength(1)
  })

  test("reports both problems in one list", t => {
    t
    ->expect(renderWarnings(<Items keys=[Some("a"), Some("a"), None] />))
    ->Expect.Array.toHaveLength(2)
  })

  test("doesn't warn about a list of one", t => {
    t->expect(renderWarnings(<Items keys=[None] />))->Expect.toEqual([])
  })

  test("doesn't warn about unkeyed static children", t => {
    let warnings = renderWarnings(
      <div id="root">
        <ul id="static">
          <li id="a" />
          <li id="b" />
        </ul>
        <>
          <Item />
          <Item />
        </>
        <TestJsx.Fragment key="f">
          <Item />
          <Item />
        </TestJsx.Fragment>
      </div>,
    )
    t->expect(warnings)->Expect.toEqual([])
  })

  test("checks a Jsx.array list inside static children, but not the static children", t => {
    let list = keys =>
      <ul id="mixed">
        <li id="first" />
        {keys->Array.map(key => <li key id=key />)->TestJsx.array}
        <li id="last" />
      </ul>
    t->expect(renderWarnings(list(["a", "b"])))->Expect.toEqual([])
    t
    ->expect(
      renderWarnings(
        <ul id="mixed">
          <li id="first" />
          {[<li id="a" />, <li id="b" />]->TestJsx.array}
        </ul>,
      ),
    )
    ->Expect.Array.toHaveLength(1)
  })

  test("doesn't warn about text or empty children, which can't take keys", t => {
    let warnings = renderWarnings(
      <ul id="text">
        {[TestJsx.string("a"), TestJsx.null, TestJsx.int(1), TestJsx.null]->TestJsx.array}
      </ul>,
    )
    t->expect(warnings)->Expect.toEqual([])
  })
})

type console

@val external console: console = "console"
@get external consoleError: console => string => unit = "error"
@set external setConsoleError: (console, string => unit) => unit = "error"

describe("KeyWarnings: output", () => {
  test("warnings go to console.error by default", t => {
    let original = console->consoleError
    let logged = []
    console->setConsoleError(message => logged->Array.push(message))
    TestRenderer.render(TestRenderer.create(), <Items keys=[None, None] />)
    console->setConsoleError(original)
    t->expect(logged)->Expect.Array.toHaveLength(1)
  })
})
