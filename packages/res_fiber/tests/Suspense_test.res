@@jsxConfig({version: 4, module_: "TestJsx"})

open Vitest

/** A promise and the functions that settle it. */
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

/** Lets promise callbacks and the renders they schedule run, then flushes the rest. */
let settle = async () => {
  await Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)
  TestRenderer.act(() => ())
}

module Reads = {
  @jsx.component
  let make = (~promise: promise<string>, ~id: string) =>
    <span id> {TestJsx.string(Hooks.use(promise))} </span>
}

let loading = <i id="loading"> {TestJsx.string("loading")} </i>

describe("Suspense", () => {
  testAsync("shows the fallback until the promise resolves, then the children", async t => {
    let data = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <div id="page">
        <Suspense fallback=loading>
          <Reads promise=data.promise id="data" />
        </Suspense>
        <b id="other" />
      </div>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div id="page"><i id="loading">loading</i><b id="other"></b></div>`)
    data.resolve("hello")
    await settle()
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<div id="page"><span id="data">hello</span><b id="other"></b></div>`)
  })

  testAsync("a promise that has settled is read straight away", async t => {
    let data = deferred()
    let first = TestRenderer.create()
    TestRenderer.render(
      first,
      <Suspense fallback=loading>
        <Reads promise=data.promise id="a" />
      </Suspense>,
    )
    data.resolve("ready")
    await settle()
    let second = TestRenderer.create()
    TestRenderer.render(
      second,
      <Suspense fallback=loading>
        <Reads promise=data.promise id="b" />
      </Suspense>,
    )
    t->expect(TestRenderer.toString(second))->Expect.toBe(`<span id="b">ready</span>`)
  })

  testAsync("waits for every suspending child", async t => {
    let a = deferred()
    let b = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Suspense fallback=loading>
        <Reads promise=a.promise id="a" />
        <Reads promise=b.promise id="b" />
      </Suspense>,
    )
    a.resolve("A")
    await settle()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<i id="loading">loading</i>`)
    b.resolve("B")
    await settle()
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<span id="a">A</span><span id="b">B</span>`)
  })

  testAsync("a rejected promise goes to the error boundary", async t => {
    let data = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ErrorBoundary
        fallback={(~error, ~reset as _) => TestJsx.string(ErrorBoundary.message(error))}
      >
        <Suspense fallback=loading>
          <Reads promise=data.promise id="data" />
        </Suspense>
      </ErrorBoundary>,
    )
    data.reject(JsError.make("load failed"))
    await settle()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("load failed")
  })

  test("the nearest boundary shows its fallback", t => {
    let data = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Suspense fallback={TestJsx.string("outer")}>
        <b id="kept" />
        <Suspense fallback={TestJsx.string("inner")}>
          <Reads promise=data.promise id="data" />
        </Suspense>
      </Suspense>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<b id="kept"></b>inner`)
  })

  test("a fallback that suspends goes to the next boundary up", t => {
    let data = deferred()
    let other = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Suspense fallback={TestJsx.string("outer")}>
        <Suspense fallback={<Reads promise=other.promise id="fallback" />}>
          <Reads promise=data.promise id="data" />
        </Suspense>
      </Suspense>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("outer")
  })

  test("with no Suspense boundary, suspending is an error", t => {
    let data = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ErrorBoundary
        fallback={(~error, ~reset as _) => TestJsx.string(ErrorBoundary.message(error))}
      >
        <Reads promise=data.promise id="data" />
      </ErrorBoundary>,
    )
    t
    ->expect(TestRenderer.toString(renderer)->String.includes("no <Suspense> boundary"))
    ->Expect.toBe(true)
    t
    ->expect(
      () => TestRenderer.render(TestRenderer.create(), <Reads promise=data.promise id="data" />),
    )
    ->Expect.toThrow(~message="no <Suspense> boundary")
  })

  test("context provided inside the boundary is unwound", t => {
    let theme = Context.make("default")
    module ThemeProvider = {
      let make = Context.provider(theme)
    }
    module Label = {
      @jsx.component
      let make = () => <u id="label"> {TestJsx.string(Hooks.useContext(theme))} </u>
    }
    let data = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <>
        <Suspense fallback=loading>
          <ThemeProvider value="inner">
            <Reads promise=data.promise id="data" />
          </ThemeProvider>
        </Suspense>
        <Label />
      </>,
    )
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<i id="loading">loading</i><u id="label">default</u>`)
  })

  testAsync("children's effects wait until they're shown", async t => {
    let ran = ref(0)
    module WithEffect = {
      @jsx.component
      let make = () => {
        Hooks.useEffect0(
          () => {
            ran := ran.contents + 1
            None
          },
        )
        TestJsx.null
      }
    }
    let data = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Suspense fallback=loading>
        <WithEffect />
        <Reads promise=data.promise id="data" />
      </Suspense>,
    )
    t->expect(ran.contents)->Expect.toBe(0)
    data.resolve("done")
    await settle()
    t->expect(ran.contents)->Expect.toBe(1)
  })

  testAsync("children that suspend on an update show the fallback, then come back", async t => {
    let ready = deferred()
    ready.resolve("first")
    let renderer = TestRenderer.create()
    let view = promise =>
      <Suspense fallback=loading>
        <Reads promise id="data" />
      </Suspense>
    // Even a resolved promise suspends the first time it's used: its result can only be read
    // asynchronously.
    TestRenderer.render(renderer, view(ready.promise))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<i id="loading">loading</i>`)
    await settle()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<span id="data">first</span>`)
    let next = deferred()
    TestRenderer.render(renderer, view(next.promise))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<i id="loading">loading</i>`)
    next.resolve("second")
    await settle()
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<span id="data">second</span>`)
  })

  test("use outside a component throws", t => {
    t
    ->expect(() => Hooks.use(Promise.resolve(1)))
    ->Expect.toThrow(~message="hooks can only be called while a function component is rendering")
  })
})

/** A counter whose setter tests can reach, to show state surviving behind a fallback. */
let setCount: ref<(int => int) => unit> = ref(_ => ())

module Counter = {
  @jsx.component
  let make = () => {
    let (count, set) = Hooks.useState(() => 0)
    setCount := set
    <b id="counter"> {TestJsx.int(count)} </b>
  }
}

/**
A resolved promise that `use` already knows the value of. (In a record: an `async` function
returning a promise directly would hand back its value instead.)
*/
type known = {promise: promise<string>}

let known = async (value: string): known => {
  let data = deferred()
  data.resolve(value)
  let renderer = TestRenderer.create()
  TestRenderer.render(
    renderer,
    <Suspense fallback=loading>
      <Reads promise=data.promise id="probe" />
    </Suspense>,
  )
  await settle()
  {promise: data.promise}
}

describe("Suspense: children already shown", () => {
  testAsync("are hidden behind the fallback, not unmounted, and keep their state", async t => {
    let first = (await known("first")).promise
    let renderer = TestRenderer.create()
    let view = promise =>
      <Suspense fallback=loading>
        <Counter />
        <Reads promise id="data" />
        {TestJsx.string("tail")}
      </Suspense>
    TestRenderer.render(renderer, view(first))
    TestRenderer.act(() => setCount.contents(c => c + 1))
    let counter = TestRenderer.findById(renderer, "counter")->Option.map(TestRenderer.uid)
    TestRenderer.clearOps(renderer)

    let next = deferred()
    TestRenderer.render(renderer, view(next.promise))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<i id="loading">loading</i>`)
    let ops = TestRenderer.ops(renderer)
    t
    ->expect(ops->Array.filter(op => op->String.startsWith("hide")))
    ->Expect.toEqual(["hide b#counter", "hide span#data", `hide "tail"`])
    t->expect(ops->Array.some(op => op->String.startsWith("remove")))->Expect.toBe(false)

    next.resolve("second")
    await settle()
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<b id="counter">1</b><span id="data">second</span>tail`)
    // The same node, with the state it had.
    t
    ->expect(TestRenderer.findById(renderer, "counter")->Option.map(TestRenderer.uid))
    ->Expect.toEqual(counter)
  })

  testAsync("an update made while hidden shows when they're shown again", async t => {
    let first = (await known("first")).promise
    let renderer = TestRenderer.create()
    let view = promise =>
      <Suspense fallback=loading>
        <Counter />
        <Reads promise id="data" />
      </Suspense>
    TestRenderer.render(renderer, view(first))
    let next = deferred()
    TestRenderer.render(renderer, view(next.promise))
    // Doesn't render (or loop): the counter is hidden.
    TestRenderer.act(() => setCount.contents(c => c + 5))
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<i id="loading">loading</i>`)
    next.resolve("second")
    await settle()
    t
    ->expect(TestRenderer.toString(renderer))
    ->Expect.toBe(`<b id="counter">5</b><span id="data">second</span>`)
  })

  testAsync("on first mount there's nothing to hide", async t => {
    let data = deferred()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Suspense fallback=loading>
        <Counter />
        <Reads promise=data.promise id="data" />
      </Suspense>,
    )
    t
    ->expect(TestRenderer.ops(renderer)->Array.some(op => op->String.startsWith("hide")))
    ->Expect.toBe(false)
    t->expect(TestRenderer.findById(renderer, "counter"))->Expect.toBe(None)
  })

  testAsync(
    "a nested boundary's hidden children stay hidden when the outer one shows again",
    async t => {
      let shown = (await known("shown")).promise
      let renderer = TestRenderer.create()
      let view = (~inner, ~outer) =>
        <Suspense fallback={TestJsx.string("outer loading")}>
          <Reads promise=outer id="outer" />
          <Suspense fallback={TestJsx.string("inner loading")}>
            <Reads promise=inner id="inner" />
          </Suspense>
        </Suspense>
      TestRenderer.render(renderer, view(~inner=shown, ~outer=shown))
      let inner = deferred()
      TestRenderer.render(renderer, view(~inner=inner.promise, ~outer=shown))
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe(`<span id="outer">shown</span>inner loading`)
      let outer = deferred()
      TestRenderer.render(renderer, view(~inner=inner.promise, ~outer=outer.promise))
      t->expect(TestRenderer.toString(renderer))->Expect.toBe("outer loading")
      outer.resolve("back")
      await settle()
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe(`<span id="outer">back</span>inner loading`)
      inner.resolve("done")
      await settle()
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe(`<span id="outer">back</span><span id="inner">done</span>`)
    },
  )
})
