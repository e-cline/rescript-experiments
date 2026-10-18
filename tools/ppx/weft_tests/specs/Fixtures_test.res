@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
What the compiled fixtures do: every `@weft.component` behaves as the `@jsx.component` it was
replaced with.
*/

open Vitest

module TestRenderer = WeftCore.TestRenderer

let render = element => {
  let renderer = TestRenderer.create()
  TestRenderer.act(() => TestRenderer.render(renderer, element))
  TestRenderer.toString(renderer)
}

describe("@weft.component", () => {
  test("with no argument, renders exactly as @jsx.component does", t => {
    let children = <p> {WeftCore.TestJsx.string("body")} </p>
    t
    ->expect(render(<Shared.ViaWeft name="a"> children </Shared.ViaWeft>))
    ->Expect.toBe(render(<Shared.ViaJsx name="a"> children </Shared.ViaJsx>))
  })

  test("generates a props type of the same shape as @jsx.component", t => {
    // Annotated, so this doesn't compile unless both have a `props` type with the same parameters
    // and fields. (They can't be the same type: records are nominal.)
    let children = <p> {WeftCore.TestJsx.string("body")} </p>
    let viaWeft: Shared.ViaWeft.props<string, WeftCore.Element.t> = {name: "a", children}
    let viaJsx: Shared.ViaJsx.props<string, WeftCore.Element.t> = {name: "a", children}
    t->expect(viaWeft.name)->Expect.toBe(viaJsx.name)
  })

  test("renders every kind, for now as a shared component", t => {
    t
    ->expect(render(<Page />))
    ->Expect.toBe(
      render(
        <section id="page">
          <h1> {WeftCore.TestJsx.string("page")} </h1>
          <h2> {WeftCore.TestJsx.string("Kinds")} </h2>
          <output> {WeftCore.TestJsx.int(3)} </output>
          <button> {WeftCore.TestJsx.string("Go")} </button>
          <p className="alert"> {WeftCore.TestJsx.string("Oops")} </p>
          <p> {WeftCore.TestJsx.string("Hello, Weft!")} </p>
        </section>,
      ),
    )
  })

  test("keeps keys, as on any component", t => {
    let labels = ["a", "b", "c"]
    let list = labels =>
      WeftCore.TestJsx.array(labels->Array.map(label => <Kinds.Nested key=label label />))
    let renderer = TestRenderer.create()
    TestRenderer.act(() => TestRenderer.render(renderer, <div> {list(labels)} </div>))
    TestRenderer.clearOps(renderer)
    TestRenderer.act(() => TestRenderer.render(renderer, <div> {list(["c", "a", "b"])} </div>))
    // A move, not three new buttons.
    t
    ->expect(TestRenderer.ops(renderer)->Array.some(op => op->String.startsWith("create")))
    ->Expect.toBe(false)
  })
})
