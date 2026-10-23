@@jsxConfig({version: 4, module_: "TestJsx"})

/***
`Hooks.useId`: an ID per call, kept for the component's lifetime. On the server
(`ServerRender.renderComponent`) and while hydrating, it comes from the component's position in the
tree, so the two agree; a component mounted on the client gets one from a count, which nothing
positioned can have. (That the HTML renderer's positions are the reconciler's is checked over random
trees in `weft_dom`'s hydration fuzz test.)
*/

open Vitest

let text = TestJsx.string

module Probe = {
  /** Takes two IDs, records them under `name`, and shows them. */
  @jsx.component
  let make = (~name: string, ~ids: dict<(string, string)>) => {
    let first = Hooks.useId()
    let second = Hooks.useId()
    let (count, setCount) = Hooks.useState(() => 0)
    ids->Dict.set(name, (first, second))
    <button id=name onClick={() => setCount(count => count + 1)}> {TestJsx.int(count)} </button>
  }
}

let idsOf = (ids, name) => ids->Dict.get(name)->Option.getOrThrow

module Reads = {
  @jsx.component
  let make = (~promise: promise<string>) => text(Hooks.use(promise))
}

type deferred = {promise: promise<string>, resolve: string => unit}
let deferred = () => {
  let resolve = ref(_ => ())
  let promise = Promise.make((done, _) => resolve := done)
  {promise, resolve: value => resolve.contents(value)}
}

let settle = async () =>
  for _ in 1 to 3 {
    await Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)
    TestRenderer.act(() => ())
  }

describe("useId", () => {
  test("gives each call its own ID, kept across renders", t => {
    let ids = Dict.make()
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Probe name="a" ids />)
    let (first, second) = idsOf(ids, "a")
    t->expect(first == second)->Expect.toBe(false)
    TestRenderer.click(renderer, "a")
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<button id="a">1</button>`)
    t->expect(idsOf(ids, "a"))->Expect.toEqual((first, second))
  })

  test("gives a component mounted where a moved one was an ID of its own", t => {
    let ids = Dict.make()
    let renderer = TestRenderer.create()
    let list = names =>
      <div>
        {names
        ->Array.map(name => <Probe key=name name ids />)
        ->TestJsx.array}
      </div>
    TestRenderer.render(renderer, list(["a", "b"]))
    let a = idsOf(ids, "a")
    let b = idsOf(ids, "b")
    // `c` mounts at `a`'s old index.
    TestRenderer.render(renderer, list(["c", "b", "a"]))
    t->expect((idsOf(ids, "a"), idsOf(ids, "b")))->Expect.toEqual((a, b))
    let all = ["a", "b", "c"]->Array.flatMap(
      name => {
        let (first, second) = idsOf(ids, name)
        [first, second]
      },
    )
    t->expect(Set.fromArray(all)->Set.size)->Expect.toBe(6)
  })

  test("on the server, makes the ID from the position it's given, and the prefix", t => {
    let ids = Dict.make()
    let _ = ServerRender.renderComponent(
      Probe.make,
      {name: "a", ids},
      {contexts: [], position: [0, 3, 0, 0, 0, 40], idPrefix: "p"},
    )
    // An index below 32 is a digit, a larger one `w..x`, three zeros or more `y<count>x`.
    t->expect(idsOf(ids, "a"))->Expect.toEqual(("p-03y3xw18x-0", "p-03y3xw18x-1"))
    let _ = ServerRender.renderComponent(Probe.make, {name: "b", ids}, {contexts: []})
    t->expect(idsOf(ids, "b"))->Expect.toEqual(("w--0", "w--1"))
  })

  test("hydrating, makes the IDs the server would from the same positions", t => {
    let ids = Dict.make()
    let element =
      <div>
        <Probe name="a" ids />
        {text("between")}
        <Suspense fallback={text("loading")}>
          <Probe name="b" ids />
        </Suspense>
      </div>
    let _ = TestRenderer.hydrate(
      `<div><button id="a">0</button>between<!--$--><button id="b">0</button><!--/$--></div>`,
      element,
    )
    let server = (name, position) => {
      let serverIds = Dict.make()
      let _ = ServerRender.renderComponent(
        Probe.make,
        {name, ids: serverIds},
        {contexts: [], position},
      )
      idsOf(serverIds, name)
    }
    // The `div` at 0; `a` at 0 in it; the boundary at 2, its content 0, and `b` at 0 in that.
    t->expect(idsOf(ids, "a"))->Expect.toEqual(server("a", [0, 0]))
    t->expect(idsOf(ids, "b"))->Expect.toEqual(server("b", [0, 2, 0, 0]))
    t->expect(idsOf(ids, "a"))->Expect.toEqual(("w-00-0", "w-00-1"))
  })

  testAsync("keeps a boundary's content's IDs while it shows its fallback, and after", async t => {
    let ids = Dict.make()
    let renderer = TestRenderer.create()
    let page = promise =>
      <Suspense fallback={text("loading")}>
        <Probe name="a" ids />
        <Reads promise />
      </Suspense>
    TestRenderer.render(renderer, page(Promise.resolve("ready")))
    await settle()
    let before = idsOf(ids, "a")
    // Suspending again (not in a transition): the fallback, with the content kept, hidden.
    let next = deferred()
    TestRenderer.render(renderer, page(next.promise))
    t->expect(TestRenderer.toString(renderer)->String.includes("loading"))->Expect.toBe(true)
    next.resolve("again")
    await settle()
    t->expect(TestRenderer.toString(renderer)->String.includes("again"))->Expect.toBe(true)
    t->expect(idsOf(ids, "a"))->Expect.toEqual(before)
  })
})
