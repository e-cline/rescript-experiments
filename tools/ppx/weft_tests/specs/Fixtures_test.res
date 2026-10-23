@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})

/***
What the compiled fixtures do: every `@weft.component` behaves as the `@jsx.component` it was
replaced with, async server components return `Lazy` elements, and entrypoints carry their ids.
*/

open Vitest

module TestRenderer = WeftCore.TestRenderer

let render = element => {
  let renderer = TestRenderer.create()
  TestRenderer.act(() => TestRenderer.render(renderer, element))
  TestRenderer.toString(renderer)
}

let tick = () => Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)

let fixture = name => `@e-cline/ppx_weft_tests/fixtures/${name}`

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

  test("renders every kind through JSX", t => {
    t
    ->expect(render(<Page />))
    ->Expect.toBe(
      render(
        <section id="page">
          <h1> {WeftCore.TestJsx.string("page")} </h1>
          <h2> {WeftCore.TestJsx.string("Kinds")} </h2>
          <output> {WeftCore.TestJsx.int(3)} </output>
          <button> {WeftCore.TestJsx.string("Go")} </button>
          <button title="pressed"> {WeftCore.TestJsx.string("Press")} </button>
          <p className="alert"> {WeftCore.TestJsx.string("Oops")} </p>
          <i> {WeftCore.TestJsx.string("shared")} </i>
          <p> {WeftCore.TestJsx.string("Hello, Weft!")} </p>
        </section>,
      ),
    )
  })

  test("keeps keys, as on any component", t => {
    let list = labels =>
      WeftCore.TestJsx.array(labels->Array.map(label => <Entrypoints.Nested key=label label />))
    let renderer = TestRenderer.create()
    TestRenderer.act(() => TestRenderer.render(renderer, <div> {list(["a", "b", "c"])} </div>))
    TestRenderer.clearOps(renderer)
    TestRenderer.act(() => TestRenderer.render(renderer, <div> {list(["c", "a", "b"])} </div>))
    // A move, not three new buttons.
    t
    ->expect(TestRenderer.ops(renderer)->Array.some(op => op->String.startsWith("create")))
    ->Expect.toBe(false)
  })
})

describe("@weft.component({kind: Server})", () => {
  test("a synchronous one renders as written", t => {
    t
    ->expect(render(<ServerComponents.Title title="T" />))
    ->Expect.toBe("<h2>T</h2>")
  })

  test("an async one returns a Lazy element at once, without waiting for its body", t => {
    let started = ref(false)
    let original = ServerComponents.fetchNote.contents
    ServerComponents.fetchNote :=
      (
        id => {
          started := true
          original(id)
        }
      )

    let element = ServerComponents.Note.make({id: "1"})
    ServerComponents.fetchNote := original
    let isLazy = switch WeftCore.Element.classify(element) {
    | Node({kind: Lazy}) => true
    | _ => false
    }
    t->expect(isLazy)->Expect.toBe(true)
    // The body runs straight away, up to its first `await`.
    t->expect(started.contents)->Expect.toBe(true)
  })

  // Called once and awaited, as the server renderer will. (Rendering an async server component with
  // the client reconciler would call it again on every render, each time starting a new promise to
  // wait for: they're for the server renderer only.)
  testAsync("an async one's Lazy element resolves to what its body returned", async t => {
    let await_ = async element =>
      switch WeftCore.Element.classify(element) {
      | Node({kind: Lazy} as node) => await WeftCore.Lazy.promiseOf(node)
      | _ => element
      }
    let note = await await_(ServerComponents.Note.make({id: "7"}))
    let section = await await_(
      ServerComponents.Section.make({
        heading: "More",
        children: <p> {WeftCore.TestJsx.string("child")} </p>,
      }),
    )
    t->expect(render(note))->Expect.toBe(`<article id="7"><h2>Note 7</h2></article>`)
    t->expect(render(section))->Expect.toBe("<section><h2>More</h2><p>child</p></section>")
  })

  test("isn't marked as an entrypoint", t => {
    t->expect(WeftCore.Entrypoint.idOf(ServerComponents.Title.make))->Expect.toEqual(None)
    t->expect(WeftCore.Entrypoint.idOf(ServerComponents.Note.make))->Expect.toEqual(None)
  })
})

describe("@weft.component({kind: Entrypoint})", () => {
  // These ids are made from the path bsc gives the PPX, so they're also the check that the PPX
  // sees where its source file is (verified point 4 in the plan).
  test("marks each entrypoint with its package, file and module path", t => {
    let ids = [
      WeftCore.Entrypoint.idOf(Entrypoints.make),
      WeftCore.Entrypoint.idOf(Entrypoints.Nested.make),
      WeftCore.Entrypoint.idOf(Entrypoints.Outer.Inner.make),
      WeftCore.Entrypoint.idOf(Entrypoints.Error.make),
      WeftCore.Entrypoint.idOf(WithInterface.make),
      WeftCore.Entrypoint.idOf(DomJsx.make),
    ]
    t
    ->expect(ids)
    ->Expect.toEqual([
      Some(fixture("Entrypoints.res#")),
      Some(fixture("Entrypoints.res#Nested")),
      Some(fixture("Entrypoints.res#Outer.Inner")),
      Some(fixture("Entrypoints.res#Error")),
      Some(fixture("WithInterface.res#")),
      Some(fixture("DomJsx.res#")),
    ])
  })

  test("doesn't mark the shared components next to them", t => {
    t->expect(WeftCore.Entrypoint.idOf(Entrypoints.Shared.make))->Expect.toEqual(None)
    t->expect(WeftCore.Entrypoint.idOf(Shared.ViaWeft.make))->Expect.toEqual(None)
  })
})
