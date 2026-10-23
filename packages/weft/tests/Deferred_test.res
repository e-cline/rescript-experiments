@@jsxConfig({version: 4, module_: "TestJsx"})

/***
`Deferred`: a promise whose outcome is readable the moment it's settled.
*/

open Vitest

let loading = <i id="loading"> {TestJsx.string("loading")} </i>

module Reads = {
  @weft.component
  let make = (~promise: promise<string>) => TestJsx.string(Hooks.use(promise))
}

describe("Deferred", () => {
  test("a resolved one is read by Hooks.use at once, without suspending", t => {
    let deferred = Deferred.make()
    deferred.resolve("ready")
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Suspense fallback=loading>
        <Reads promise=deferred.promise />
      </Suspense>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("ready")
  })

  test("and by a Lazy element, at once", t => {
    let deferred = Deferred.make()
    let lazy = Lazy.fromPromise(deferred.promise)
    deferred.resolve(<b id="content" />)
    let renderer = TestRenderer.create()
    TestRenderer.render(renderer, <Suspense fallback=loading> lazy </Suspense>)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<b id="content"></b>`)
  })

  testAsync("a pending one suspends, and renders once resolved", async t => {
    let deferred = Deferred.make()
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <Suspense fallback=loading>
        <Reads promise=deferred.promise />
      </Suspense>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<i id="loading">loading</i>`)
    deferred.resolve("later")
    await Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)
    TestRenderer.act(() => ())
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("later")
  })

  test("a rejected one throws its error at once, for an error boundary", t => {
    let deferred = Deferred.make()
    deferred.reject(JsError.make("no data"))
    let renderer = TestRenderer.create()
    TestRenderer.render(
      renderer,
      <ErrorBoundary
        fallback={(~error, ~reset as _) => TestJsx.string(ErrorBoundary.message(error))}
      >
        <Reads promise=deferred.promise />
      </ErrorBoundary>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("no data")
  })

  testAsync("settles once: later calls do nothing", async t => {
    let deferred = Deferred.make()
    t->expect(Deferred.isSettled(deferred))->Expect.toBe(false)
    deferred.resolve("first")
    deferred.resolve("second")
    deferred.reject(JsError.make("too late"))
    t->expect(Deferred.isSettled(deferred))->Expect.toBe(true)
    t->expect(await deferred.promise)->Expect.toBe("first")
  })
})
