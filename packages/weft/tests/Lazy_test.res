@@jsxConfig({version: 4, module_: "TestJsx"})

/***
`Lazy` elements: what they suspend on, and that they never get a fiber of their own, so a lazy and
the element it resolves to can replace each other without disturbing anything below.
*/

open Vitest

type deferred<'value> = {
  promise: promise<'value>,
  resolve: 'value => unit,
  reject: JsError.t => unit,
}

let deferred = (): deferred<'value> => {
  let resolve = ref(_ => ())
  let reject = ref(_ => ())
  let promise = Promise.make((onResolve, onReject) => {
    resolve := onResolve
    reject := onReject
  })
  {promise, resolve: value => resolve.contents(value), reject: error => reject.contents(error)}
}

let tick = () => Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)

/** Lets promise callbacks and the renders they schedule run, then flushes the rest. */
let settle = async () => {
  await tick()
  TestRenderer.act(() => ())
}

/** A lazy element that has already resolved to `element` (and been seen to, after a tick). */
let resolved = async element => {
  let lazy = Lazy.fromPromise(Promise.resolve(element))
  await tick()
  lazy
}

let loading = <i id="loading"> {TestJsx.string("loading")} </i>

/** A counter whose setter tests can reach, to show state surviving. */
let setCounts: dict<(int => int) => unit> = Dict.make()

module Counter = {
  @jsx.component
  let make = (~id: string) => {
    let (count, set) = Hooks.useState(() => 0)
    setCounts->Dict.set(id, set)
    <b id> {TestJsx.int(count)} </b>
  }
}

let bump = id => TestRenderer.act(() => (setCounts->Dict.getUnsafe(id))(c => c + 1))

let uidOf = (renderer, id) => TestRenderer.findById(renderer, id)->Option.map(TestRenderer.uid)

describe("Lazy: suspending", () => {
  testAsync(
    "a pending lazy shows the nearest boundary's fallback, then what it resolves to",
    async t => {
      let data = deferred()
      let renderer = TestRenderer.create()
      TestRenderer.render(
        renderer,
        <div id="page">
          <Suspense fallback=loading> {Lazy.fromPromise(data.promise)} </Suspense>
          <b id="other" />
        </div>,
      )
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe(`<div id="page"><i id="loading">loading</i><b id="other"></b></div>`)
      data.resolve(<span id="content"> {TestJsx.string("ready")} </span>)
      await settle()
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe(`<div id="page"><span id="content">ready</span><b id="other"></b></div>`)
    },
  )

  testAsync("a lazy whose promise has settled is rendered at once, without suspending", async t => {
    let lazy = await resolved(<span id="content" />)
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Suspense fallback=loading> lazy </Suspense>)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<span id="content"></span>`)
    t
    ->expect(TestRenderer.ops(renderer)->Array.some(op => op->String.includes("loading")))
    ->Expect.toBe(false)
  })

  testAsync("a rejected lazy throws its error, for an error boundary", async t => {
    let data = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ErrorBoundary
        fallback={(~error, ~reset as _) => TestJsx.string(ErrorBoundary.message(error))}
      >
        <Suspense fallback=loading> {Lazy.fromPromise(data.promise)} </Suspense>
      </ErrorBoundary>,
    )
    data.reject(JsError.make("no data"))
    await settle()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("no data")
  })

  testAsync(
    "a rejected lazy directly inside an error boundary is caught by that boundary",
    async t => {
      let data = deferred()
      let lazy = Lazy.fromPromise(data.promise)
      data.reject(JsError.make("no data"))
      await tick()
      let renderer = TestRenderer.create()
      TestRenderer.render(
        renderer,
        <div>
          <ErrorBoundary
            fallback={(~error, ~reset as _) => TestJsx.string(ErrorBoundary.message(error))}
          >
            lazy
          </ErrorBoundary>
          <b id="sibling" />
        </div>,
      )
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe(`<div>no data<b id="sibling"></b></div>`)
    },
  )

  testAsync("a lazy inside a host element suspends to the boundary above it", async t => {
    let data = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Suspense fallback=loading>
        <div id="box"> {Lazy.fromPromise(data.promise)} </div>
      </Suspense>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<i id="loading">loading</i>`)
    data.resolve(TestJsx.string("inside"))
    await settle()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<div id="box">inside</div>`)
  })

  testAsync("a lazy may resolve to another lazy, a list, or a fragment", async t => {
    let inner = await resolved(<b id="inner" />)
    let toLazy = await resolved(inner)
    let toList = await resolved(TestJsx.array([<i key="a" id="a" />, <i key="b" id="b" />]))
    let toFragment = await resolved(
      <>
        <u id="c" />
        <u id="d" />
      </>,
    )
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <div>
        toLazy
        toList
        toFragment
      </div>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div><b id="inner"></b><i id="a"></i><i id="b"></i><u id="c"></u><u id="d"></u></div>`)
  })

  testAsync("with no boundary, an urgent render that suspends on a lazy fails", async t => {
    let data = deferred()
    let renderer = TestRenderer.create()
    let render = () => TestRenderer.render(renderer, <div> {Lazy.fromPromise(data.promise)} </div>)
    t->expect(render)->Expect.toThrow
  })
})

describe("Lazy: no fiber of its own", () => {
  testAsync(
    "replacing a lazy with what it resolved to keeps the state and nodes below",
    async t => {
      let lazy = await resolved(<Counter id="count" />)
      let renderer = TestRenderer.create()
      TestRenderer.render(renderer, <div> lazy </div>)
      bump("count")
      let node = uidOf(renderer, "count")
      TestRenderer.clearOps(renderer)

      TestRenderer.render(
        renderer,
        <div>
          <Counter id="count" />
        </div>,
      )
      t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<div><b id="count">1</b></div>`)
      t->expect(uidOf(renderer, "count"))->Expect.toEqual(node)
      t->expect(TestRenderer.ops(renderer))->Expect.toEqual([])
    },
  )

  testAsync("and so does replacing an element with a lazy that resolved to it", async t => {
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <div>
        <Counter id="count" />
        <p id="sibling" />
      </div>,
    )
    bump("count")
    let node = uidOf(renderer, "count")
    let lazy = await resolved(<Counter id="count" />)
    TestRenderer.clearOps(renderer)

    TestRenderer.render(
      renderer,
      <div>
        lazy
        <p id="sibling" />
      </div>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div><b id="count">1</b><p id="sibling"></p></div>`)
    t->expect(uidOf(renderer, "count"))->Expect.toEqual(node)
    t->expect(TestRenderer.ops(renderer))->Expect.toEqual([])
  })

  testAsync("as the only child of a root or a component, too", async t => {
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Counter id="count" />)
    bump("count")
    TestRenderer.render(renderer, await resolved(<Counter id="count" />))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<b id="count">1</b>`)
  })

  testAsync(
    "lazies in a keyed list keep their elements' identity when the list is reordered",
    async t => {
      let item = async key => await resolved(<Counter key id=key />)
      let (a, b, c) = (await item("a"), await item("b"), await item("c"))
      let renderer = TestRenderer.create()
      TestRenderer.render(renderer, <div> {TestJsx.array([a, b, c])} </div>)
      bump("a")
      bump("c")
      let nodes = ["a", "b", "c"]->Array.map(id => uidOf(renderer, id))
      TestRenderer.clearOps(renderer)

      // Reordered, and now a mix of lazies and the elements they resolved to.
      TestRenderer.render(
        renderer,
        <div> {TestJsx.array([c, <Counter key="a" id="a" />, b])} </div>,
      )
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe(`<div><b id="c">1</b><b id="a">1</b><b id="b">0</b></div>`)
      t->expect(["a", "b", "c"]->Array.map(id => uidOf(renderer, id)))->Expect.toEqual(nodes)
      // Moved, not made again.
      t
      ->expect(TestRenderer.ops(renderer)->Array.some(op => op->String.startsWith("create")))
      ->Expect.toBe(false)
    },
  )

  testAsync(
    "a keyed list of lazies gets no key warning, and written-out lazies don't need keys",
    async t => {
      let warnings = []
      let original = KeyWarnings.warn.contents
      KeyWarnings.warn := (message => warnings->Array.push(message))
      let keyed = [await resolved(<i key="a" />), await resolved(<i key="b" />)]
      let unkeyed = (await resolved(<i />), await resolved(<u />))
      let (first, second) = unkeyed
      let renderer = TestRenderer.create()
      TestRenderer.render(renderer, <div> {TestJsx.array(keyed)} </div>)
      TestRenderer.render(
        renderer,
        <div>
          first
          second
        </div>,
      )
      KeyWarnings.warn := original
      t->expect(warnings)->Expect.toEqual([])
    },
  )
})

describe("Lazy: in a transition", () => {
  testAsync("a pending lazy keeps the old screen until it resolves", async t => {
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Suspense fallback=loading>
        <Counter id="count" />
      </Suspense>,
    )
    bump("count")
    let data = deferred()
    Transition.start(
      () =>
        TestRenderer.scheduleRender(
          renderer,
          <Suspense fallback=loading> {Lazy.fromPromise(data.promise)} </Suspense>,
        ),
    )
    TestScheduler.flushAll()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<b id="count">1</b>`)

    data.resolve(<Counter id="count" />)
    await tick()
    TestScheduler.flushAll()
    // Same position, same type: the counter kept its state.
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<b id="count">1</b>`)
  })
})
