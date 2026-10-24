@@jsxConfig({version: 4, module_: "TestJsx"})

/***
Hydration, in the reconciler, over `TestRenderer`'s nodes: markup parsed (as a server's HTML would
be), then `hydrateRoot` with the element tree. What's checked, besides what ends up rendered, is
the log of host operations: hydrating adopts the server's nodes (`hydrate ...`) and creates none,
unless something didn't match, and then only what's rendered on the client instead.

The fuzz test at the end is the oracle: random trees, hydrated over markup made from them, must end
up as a direct render of the same tree does, with no node created; and with the markup broken at
random, still end up the same (recovering by rendering on the client what didn't match).
*/

open Vitest

type deferred<'value> = {promise: promise<'value>, resolve: 'value => unit}

let deferred = (): deferred<'value> => {
  let resolve = ref(_ => ())
  let promise = Promise.make((onResolve, _) => resolve := onResolve)
  {promise, resolve: value => resolve.contents(value)}
}

let settle = async () => {
  for _ in 1 to 3 {
    await Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)
    TestRenderer.act(() => ())
  }
}

let text = TestJsx.string

type console
@val external console: console = "console"
@get external consoleError: console => 'a => unit = "error"
@set external setConsoleError: (console, string => unit) => unit = "error"

/** What `f` logs with `console.error`, and what it returns. */
let logging = (f: unit => 'a): ('a, array<string>) => {
  let original = console->consoleError
  let messages = []
  console->setConsoleError(message => messages->Array.push(message))
  switch f() {
  | result =>
    console->setConsoleError(original)
    (result, messages)
  | exception error =>
    console->setConsoleError(original)
    throw(error)
  }
}

let created = renderer =>
  TestRenderer.ops(renderer)->Array.filter(op => op->String.startsWith("create"))

/** The same tree rendered without hydrating, for comparing. */
let direct = element => {
  let renderer = TestRenderer.create()
  TestRenderer.render(renderer, element)
  TestRenderer.toString(renderer)
}

module Counter = {
  @weft.component
  let make = (~id: string) => {
    let (count, setCount) = Hooks.useState(() => 0)
    <button id onClick={() => setCount(count => count + 1)}> {TestJsx.int(count)} </button>
  }
}

module Reads = {
  @weft.component
  let make = (~promise: promise<string>, ~id: string) => <b id> {text(Hooks.use(promise))} </b>
}

describe("hydrating", () => {
  test("adopts the server's nodes, creating none", t => {
    let element =
      <div id="a">
        <p> {text("hello")} </p>
        <>
          <Counter id="c" />
        </>
      </div>
    let renderer = TestRenderer.hydrate(
      `<div id="a"><p>hello</p><button id="c">0</button></div>`,
      element,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(direct(element))
    t
    ->expect(TestRenderer.ops(renderer))
    ->Expect.toEqual(["hydrate p", "hydrate button#c", "hydrate div#a"])
  })

  test("attaches handlers, so the page works as a client-rendered one", t => {
    let renderer = TestRenderer.hydrate(`<button id="c">0</button>`, <Counter id="c" />)
    TestRenderer.clearOps(renderer)
    TestRenderer.click(renderer, "c")
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<button id="c">1</button>`)
    t->expect(TestRenderer.ops(renderer))->Expect.toEqual([`text "0" -> "1"`])
  })

  test("runs effects and attaches refs after the commit, to the server's nodes", t => {
    let log = []
    let ref: Ref.t<Nullable.t<TestJsx.node>> = {current: Nullable.null}
    module Effects = {
      @weft.component
      let make = () => {
        Hooks.useLayoutEffect0(
          () => {
            log->Array.push(
              "layout: " ++ ref.current->Nullable.toOption->Option.mapOr("", TestRenderer.tag),
            )
            None
          },
        )
        Hooks.useEffect0(
          () => {
            log->Array.push("effect")
            None
          },
        )
        <i ref> {text("x")} </i>
      }
    }
    let renderer = TestRenderer.hydrate(`<i>x</i>`, <Effects />)
    t->expect(log)->Expect.toEqual(["layout: i", "effect"])
    t->expect(created(renderer))->Expect.toEqual([])
  })

  test("takes texts apart where the server kept them apart, and makes an empty one", t => {
    module Word = {
      @weft.component
      let make = (~word: string) => text(word)
    }
    let element =
      <p>
        {text("a")}
        <Word word="b" />
        {text("")}
        {text("c")}
      </p>
    let renderer = TestRenderer.hydrate(`<p>a<!-- -->b<!-- -->c</p>`, element)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<p>abc</p>")
    // The empty one couldn't be in the HTML: it's the one node made.
    t->expect(created(renderer))->Expect.toEqual([`create ""`])
  })

  test("patches a text that differs, and warns", t => {
    let (renderer, warnings) = logging(
      () => TestRenderer.hydrate(`<p>12:00</p>`, <p> {text("12:01")} </p>),
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<p>12:01</p>")
    t->expect(created(renderer))->Expect.toEqual([])
    t
    ->expect(warnings)
    ->Expect.toEqual([
      `Weft: the server's HTML doesn't match the client's render: the text "12:00" is "12:01" on the client`,
    ])
  })

  test("removes what the client doesn't render, and warns", t => {
    let (renderer, warnings) = logging(
      () =>
        TestRenderer.hydrate(
          `<div><p>kept</p><span>extra</span></div><i>extra too</i>`,
          <div>
            <p> {text("kept")} </p>
          </div>,
        ),
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<div><p>kept</p></div>")
    t->expect(created(renderer))->Expect.toEqual([])
    t
    ->expect(TestRenderer.ops(renderer)->Array.filter(op => op->String.startsWith("remove")))
    ->Expect.toEqual(["remove span", "remove i"])
    t->expect(Array.length(warnings))->Expect.toBe(2)
  })

  test("renders the whole root on the client for a mismatch outside every boundary", t => {
    let element =
      <div>
        <p> {text("client")} </p>
      </div>
    let (renderer, warnings) = logging(
      () => TestRenderer.hydrate(`<div><span>server</span></div>`, element),
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(direct(element))
    t->expect(TestRenderer.ops(renderer)->Array.includes("clear root"))->Expect.toBe(true)
    t
    ->expect(warnings)
    ->Expect.toEqual([
      "Weft: the server's HTML doesn't match the client's render: expected <p>, found <span>. The page is rendered on the client instead.",
    ])
  })

  test("renders only the boundary on the client for a mismatch inside one", t => {
    let element =
      <main>
        <h1> {text("title")} </h1>
        <Suspense fallback={text("loading")}>
          <p> {text("client")} </p>
        </Suspense>
        <footer> {text("end")} </footer>
      </main>
    let (renderer, _) = logging(
      () =>
        TestRenderer.hydrate(
          `<main><h1>title</h1><!--$--><span>server</span><!--/$--><footer>end</footer></main>`,
          element,
        ),
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(direct(element))
    // The heading and the footer are the server's; only the boundary's content is new.
    // Children before their parents, as on any mount.
    t->expect(created(renderer))->Expect.toEqual([`create "client"`, `create p`])
    t
    ->expect(TestRenderer.toMarkup(renderer))
    ->Expect.toBe("<main><h1>title</h1><p>client</p><footer>end</footer></main>")
  })

  test("leaves components, fragments and providers' nodes to their hosts", t => {
    let theme = Context.make("plain")
    module Themed = {
      @weft.component
      let make = () => <i> {text(Hooks.useContext(theme))} </i>
    }
    let memo = Memo.memo(Counter.make)
    let element =
      <>
        {JsxCore.jsx(Context.provider(theme), {value: "dark", children: <Themed />})}
        {JsxCore.jsx(memo, {id: "m"})}
      </>
    let renderer = TestRenderer.hydrate(`<i>dark</i><button id="m">0</button>`, element)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(direct(element))
    t->expect(created(renderer))->Expect.toEqual([])
  })

  test("mounts a portal's children in its own container", t => {
    let probe = TestRenderer.create()
    let target = TestRenderer.createTarget(probe, "elsewhere")
    let element = <div> {TestRenderer.portal(target, <b> {text("away")} </b>)} </div>
    let renderer = TestRenderer.hydrate(`<div></div>`, element)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<div></div>")
    t->expect(TestRenderer.targetToString(target))->Expect.toBe("<b>away</b>")
  })

  test("reads useSyncExternalStore's server snapshot, then catches up with the store", t => {
    let subscribe = _ => () => ()
    module Store = {
      @weft.component
      let make = () =>
        <s>
          {text(
            Hooks.useSyncExternalStore(
              ~subscribe,
              ~getSnapshot=() => "client",
              ~getServerSnapshot=() => "server",
            ),
          )}
        </s>
    }
    let renderer = TestRenderer.hydrate(`<s>server</s>`, <Store />)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<s>client</s>")
    // Hydrated without a mismatch, then updated.
    t->expect(created(renderer))->Expect.toEqual([])
    t
    ->expect(TestRenderer.ops(renderer)->Array.includes(`text "server" -> "client"`))
    ->Expect.toBe(true)
  })
})

describe("hydrating boundaries", () => {
  test("hydrates a complete boundary in place, keeping its markers", t => {
    let element =
      <div>
        <Suspense fallback={text("loading")}>
          <p> {text("content")} </p>
        </Suspense>
      </div>
    let renderer = TestRenderer.hydrate(`<div><!--$--><p>content</p><!--/$--></div>`, element)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(direct(element))
    t->expect(created(renderer))->Expect.toEqual([])
    t
    ->expect(TestRenderer.toMarkup(renderer))
    ->Expect.toBe("<div><!--$--><p>content</p><!--/$--></div>")
  })

  test(
    "leaves a pending boundary as the server sent it, and hydrates it when its content comes",
    t => {
      let element =
        <div>
          <Suspense fallback={<i> {text("loading")} </i>}>
            <Counter id="c" />
          </Suspense>
          <p> {text("after")} </p>
        </div>
      let renderer = TestRenderer.hydrate(
        `<div><!--$?--><i>loading</i><!--/$--><p>after</p></div>`,
        element,
      )
      // The server's fallback, untouched: not the client's.
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe("<div><i>loading</i><p>after</p></div>")
      t->expect(created(renderer))->Expect.toEqual([])
      TestRenderer.resolveBoundary(renderer, `<button id="c">0</button>`)
      t->expect(TestRenderer.toString(renderer))->Expect.toBe(direct(element))
      t->expect(created(renderer))->Expect.toEqual([])
      // And it works.
      TestRenderer.click(renderer, "c")
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe("<div><button id=\"c\">1</button><p>after</p></div>")
    },
  )

  test("renders a pending boundary on the client when its content arrives not matching", t => {
    let element =
      <div>
        <Suspense fallback={text("loading")}>
          <p> {text("client")} </p>
        </Suspense>
        <p> {text("after")} </p>
      </div>
    let (renderer, warnings) = logging(
      () => {
        let renderer = TestRenderer.hydrate(
          `<div><!--$?--><i>loading</i><!--/$--><p>after</p></div>`,
          element,
        )
        TestRenderer.resolveBoundary(renderer, `<b>server</b>`)
        renderer
      },
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(direct(element))
    t
    ->expect(warnings)
    ->Expect.toEqual([
      "Weft: the server's HTML doesn't match the client's render: expected <p>, found <b>. The boundary is rendered on the client instead.",
    ])
  })

  test("renders a boundary that failed on the server on the client", t => {
    let element =
      <Suspense fallback={text("loading")}>
        <p> {text("client")} </p>
      </Suspense>
    let renderer = TestRenderer.hydrate(`<!--$!--><b>fallback</b><!--/$-->`, element)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(direct(element))
    t
    ->expect(TestRenderer.ops(renderer)->Array.includes("clear a boundary's server content"))
    ->Expect.toBe(true)
  })

  describe(
    "a boundary that failed on the server, whose error an error boundary above catches",
    () => {
      module Throws = {
        @weft.component
        let make = () => JsError.throwWithMessage("broken")
      }
      let caught =
        <ErrorBoundary
          fallback={(~error, ~reset as _) => <em> {text(ErrorBoundary.message(error))} </em>}
        >
          <Suspense fallback={text("loading")}>
            <Throws />
          </Suspense>
        </ErrorBoundary>

      test(
        "renders the boundary around the error boundary on the client",
        t => {
          let element =
            <div>
              <Suspense fallback={text("outer")}> caught </Suspense>
              <p> {text("kept")} </p>
            </div>
          let (renderer, _) = logging(
            () =>
              TestRenderer.hydrate(
                `<div><!--$--><!--$!-->loading<!--/$--><!--/$--><p>kept</p></div>`,
                element,
              ),
          )
          t
          ->expect(TestRenderer.toString(renderer))
          ->Expect.toBe("<div><em>broken</em><p>kept</p></div>")
          t->expect(TestRenderer.ops(renderer)->Array.includes("hydrate p"))->Expect.toBe(true)
          t->expect(created(renderer))->Expect.toEqual([`create "broken"`, "create em"])
        },
      )

      test(
        "renders the boundary around it on the client when its content streams in later",
        t => {
          let element =
            <div>
              <Suspense fallback={text("outer")}> caught </Suspense>
              <p> {text("kept")} </p>
            </div>
          let (renderer, _) = logging(
            () => {
              let renderer = TestRenderer.hydrate(
                `<div><!--$?-->outer<!--/$--><p>kept</p></div>`,
                element,
              )
              TestRenderer.resolveBoundary(renderer, `<!--$!-->loading<!--/$-->`)
              renderer
            },
          )
          t
          ->expect(TestRenderer.toString(renderer))
          ->Expect.toBe("<div><em>broken</em><p>kept</p></div>")
          t->expect(TestRenderer.ops(renderer)->Array.includes("hydrate p"))->Expect.toBe(true)
        },
      )

      test(
        "renders the root on the client, with no boundary around the error boundary",
        t => {
          let element =
            <div>
              caught
              <p> {text("kept")} </p>
            </div>
          let (renderer, _) = logging(
            () => TestRenderer.hydrate(`<div><!--$!-->loading<!--/$--><p>kept</p></div>`, element),
          )
          t
          ->expect(TestRenderer.toString(renderer))
          ->Expect.toBe("<div><em>broken</em><p>kept</p></div>")
        },
      )
    },
  )

  test("renders a pending boundary that fails later on the client", t => {
    let element =
      <Suspense fallback={text("loading")}>
        <p> {text("client")} </p>
      </Suspense>
    let renderer = TestRenderer.hydrate(`<!--$?-->loading<!--/$-->`, element)
    TestRenderer.failBoundary(renderer)
    t->expect(TestRenderer.toString(renderer))->Expect.toBe(direct(element))
  })

  testAsync(
    "keeps the server's content when hydrating it suspends, and hydrates once it can",
    async t => {
      let data = deferred()
      let element =
        <Suspense fallback={text("loading")}>
          <Reads promise=data.promise id="r" />
        </Suspense>
      let renderer = TestRenderer.hydrate(`<!--$--><b id="r">ready</b><!--/$-->`, element)
      // Not the client's fallback over content the server already sent.
      t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<b id="r">ready</b>`)
      data.resolve("ready")
      await settle()
      t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<b id="r">ready</b>`)
      t->expect(created(renderer))->Expect.toEqual([])
      t->expect(TestRenderer.ops(renderer)->Array.includes("hydrate b#r"))->Expect.toBe(true)
    },
  )

  testAsync(
    "keeps a pending boundary's content when hydrating it suspends once it arrives, and hydrates it later",
    async t => {
      // An entrypoint's chunk still loading when the boundary's content streams in, say.
      let data = deferred()
      let element =
        <div>
          <Suspense fallback={<i> {text("loading")} </i>}>
            <Reads promise=data.promise id="r" />
          </Suspense>
          <p> {text("after")} </p>
        </div>
      let (renderer, warnings) = logging(
        () => {
          let renderer = TestRenderer.hydrate(
            `<div><!--$?--><i>loading</i><!--/$--><p>after</p></div>`,
            element,
          )
          TestRenderer.resolveBoundary(renderer, `<b id="r">ready</b>`)
          renderer
        },
      )
      // The server's content, as it arrived: not the client's fallback, nor a copy after it.
      t
      ->expect(TestRenderer.toMarkup(renderer))
      ->Expect.toBe(`<div><!--$--><b id="r">ready</b><!--/$--><p>after</p></div>`)
      data.resolve("ready")
      await settle()
      t
      ->expect(TestRenderer.toMarkup(renderer))
      ->Expect.toBe(`<div><!--$--><b id="r">ready</b><!--/$--><p>after</p></div>`)
      t->expect(created(renderer))->Expect.toEqual([])
      t->expect(TestRenderer.ops(renderer)->Array.includes("hydrate b#r"))->Expect.toBe(true)
      t->expect(warnings)->Expect.toEqual([])
    },
  )

  testAsync(
    "keeps a boundary waiting to hydrate as the server rendered it while something beside it updates",
    async t => {
      let data = deferred()
      let element =
        <div>
          <Counter id="c" />
          <Suspense fallback={text("loading")}>
            <Reads promise=data.promise id="r" />
          </Suspense>
        </div>
      let (renderer, warnings) = logging(
        () => {
          let renderer = TestRenderer.hydrate(
            `<div><button id="c">0</button><!--$--><b id="r">ready</b><!--/$--></div>`,
            element,
          )
          TestRenderer.click(renderer, "c")
          renderer
        },
      )
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe(`<div><button id="c">1</button><b id="r">ready</b></div>`)
      t->expect(warnings)->Expect.toEqual([])
      data.resolve("ready")
      await settle()
      t
      ->expect(TestRenderer.toString(renderer))
      ->Expect.toBe(`<div><button id="c">1</button><b id="r">ready</b></div>`)
      t->expect(created(renderer))->Expect.toEqual([])
      t->expect(TestRenderer.ops(renderer)->Array.includes("hydrate b#r"))->Expect.toBe(true)
    },
  )

  testAsync(
    "waits, with the server's content, for what suspends outside every boundary",
    async t => {
      let data = deferred()
      let renderer = TestRenderer.hydrate(
        `<b id="r">ready</b>`,
        <Reads promise=data.promise id="r" />,
      )
      t->expect(TestRenderer.toString(renderer))->Expect.toBe(`<b id="r">ready</b>`)
      t->expect(TestRenderer.ops(renderer))->Expect.toEqual([])
      data.resolve("ready")
      await settle()
      t->expect(TestRenderer.ops(renderer))->Expect.toEqual(["hydrate b#r"])
    },
  )

  test("renders a dehydrated boundary on the client when it gets new props first", t => {
    let renderer = TestRenderer.hydrate(
      `<!--$?-->loading<!--/$-->`,
      <Suspense fallback={text("loading")}>
        <p> {text("first")} </p>
      </Suspense>,
    )
    TestRenderer.render(
      renderer,
      <Suspense fallback={text("loading")}>
        <p> {text("second")} </p>
      </Suspense>,
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<p>second</p>")
  })

  test(
    "inserts before a dehydrated boundary's server content, and removes it with the boundary",
    t => {
      let boundary =
        <Suspense key="b" fallback={text("loading")}>
          <p> {text("content")} </p>
        </Suspense>
      let renderer = TestRenderer.hydrate(
        `<div><!--$?-->loading<!--/$--></div>`,
        <div> boundary </div>,
      )
      // The same boundary element (by key, with the same props), so it stays dehydrated; something
      // new goes before it.
      TestRenderer.render(
        renderer,
        <div>
          <h1 key="h"> {text("new")} </h1>
          boundary
        </div>,
      )
      t
      ->expect(TestRenderer.toMarkup(renderer))
      ->Expect.toBe("<div><h1>new</h1><!--$?-->loading<!--/$--></div>")
      TestRenderer.render(
        renderer,
        <div>
          <h1> {text("new")} </h1>
        </div>,
      )
      t->expect(TestRenderer.toMarkup(renderer))->Expect.toBe("<div><h1>new</h1></div>")
    },
  )

  test("gives an error to the client to throw again, where an error boundary catches it", t => {
    module Throws = {
      @weft.component
      let make = () => JsError.throwWithMessage("broken")
    }
    let element =
      <div>
        <Suspense fallback={text("loading")}>
          <ErrorBoundary
            fallback={(~error, ~reset as _) => <em> {text(ErrorBoundary.message(error))} </em>}
          >
            <Throws />
          </ErrorBoundary>
        </Suspense>
        <p> {text("kept")} </p>
      </div>
    let (renderer, _) = logging(
      () => TestRenderer.hydrate(`<div><!--$--><em>broken</em><!--/$--><p>kept</p></div>`, element),
    )
    t->expect(TestRenderer.toString(renderer))->Expect.toBe("<div><em>broken</em><p>kept</p></div>")
    t->expect(TestRenderer.ops(renderer)->Array.includes("hydrate p"))->Expect.toBe(true)
  })
})

// The fuzz test

/** A seeded Lehmer PRNG (as in the other fuzz tests), so failures reproduce. */
module Random = {
  type t = ref<float>
  let make = (seed: float): t => ref(seed)
  let next = (state: t): float => {
    let product = state.contents *. 48271.0
    state := product -. 2147483647.0 *. Math.floor(product /. 2147483647.0)
    state.contents
  }
  let intBelow = (state: t, bound: int): int => mod(Float.toInt(next(state)), bound)
  let pick = (state: t, items: array<'a>): 'a =>
    items->Array.getUnsafe(intBelow(state, Array.length(items)))
}

type rec spec =
  | Host(string, option<string>, array<spec>)
  | Text(string)
  | Stateful(spec)
  | Fragment(array<spec>)
  | Boundary(array<spec>)

module Stateful = {
  @weft.component
  let make = (~children: Element.t) => {
    let (title, _) = Hooks.useState(() => "s")
    <span title> children </span>
  }
}

let rec generate = (random, ~depth) =>
  switch Random.intBelow(random, depth <= 0 ? 2 : 6) {
  | 0 => Text(Random.pick(random, ["a", "b", "", "c d"]))
  | 1 => Host(Random.pick(random, ["i", "b"]), None, [])
  | 2 => Stateful(generate(random, ~depth=depth - 1))
  | 3 => Fragment(children(random, ~depth))
  | 4 => Boundary(children(random, ~depth))
  | _ =>
    Host(
      Random.pick(random, ["div", "p", "ul"]),
      Random.intBelow(random, 2) == 0 ? Some(Random.pick(random, ["x", "y"])) : None,
      children(random, ~depth),
    )
  }

and children = (random, ~depth) =>
  Array.fromInitializer(~length=Random.intBelow(random, 4), _ => generate(random, ~depth=depth - 1))

let rec toElement = spec =>
  switch spec {
  | Text(value) => text(value)
  | Host(tag, id, children) =>
    let children = children->Array.map(toElement)
    JsxCore.markStaticList(children)
    let props: TestJsx.Elements.props = switch id {
    | Some(id) => {id, children: JsxCore.array(children)}
    | None => {children: JsxCore.array(children)}
    }
    JsxCore.hostJsx(tag, props)
  | Stateful(child) => <Stateful> {toElement(child)} </Stateful>
  | Fragment(children) =>
    let children = children->Array.map(toElement)
    JsxCore.markStaticList(children)
    <> {JsxCore.array(children)} </>
  | Boundary(children) =>
    let children = children->Array.map(toElement)
    JsxCore.markStaticList(children)
    <Suspense fallback={text("loading")}> {JsxCore.array(children)} </Suspense>
  }

type mutation = {mutable target: int, mutable seen: int, kind: int}

/**
The markup a server would send for `spec` (in `TestRenderer`'s format, with markers and text
separators), with the `target`th host or text broken by `mutation`'s `kind` if there is one.
*/
let toMarkup = (spec, ~mutation: option<mutation>) => {
  let out = []
  let lastWasText = ref(false)
  let markup = text => {
    out->Array.push(text)
    lastWasText := false
  }
  let mutate = () =>
    switch mutation {
    | Some(mutation) =>
      mutation.seen = mutation.seen + 1
      mutation.seen - 1 == mutation.target ? Some(mutation.kind) : None
    | None => None
    }
  let rec write = spec =>
    switch spec {
    | Text("") => ()
    | Text(value) =>
      let value = switch mutate() {
      | Some(1) => ""
      | Some(_) => value ++ "!"
      | None => value
      }
      if value != "" {
        if lastWasText.contents {
          out->Array.push("<!-- -->")
        }
        out->Array.push(value)
        lastWasText := true
      }
    | Host(tag, id, children) =>
      switch mutate() {
      | Some(0) => markup("<em></em>")
      | Some(1) => ()
      | Some(2) =>
        writeHost(tag, id, children)
        markup("<q>extra</q>")
      | _ => writeHost(tag, id, children)
      }
    | Stateful(child) =>
      markup(`<span title="s">`)
      write(child)
      markup("</span>")
    | Fragment(children) => children->Array.forEach(write)
    | Boundary(children) =>
      markup("<!--$-->")
      children->Array.forEach(write)
      markup("<!--/$-->")
    }
  and writeHost = (tag, id, children) => {
    markup(`<${tag}${id->Option.mapOr("", id => ` id="${id}"`)}>`)
    children->Array.forEach(write)
    markup(`</${tag}>`)
  }
  write(spec)
  out->Array.join("")
}

let rec countTargets = spec =>
  switch spec {
  | Text("") => 0
  | Text(_) => 1
  | Host(_, _, children) => 1 + children->Array.reduce(0, (sum, child) => sum + countTargets(child))
  | Stateful(child) => countTargets(child)
  | Fragment(children) | Boundary(children) =>
    children->Array.reduce(0, (sum, child) => sum + countTargets(child))
  }

describe("hydrating, fuzzed", () => {
  test("random trees hydrate into what a direct render makes, with no node created", t => {
    for seed in 1 to 300 {
      let random = Random.make(Int.toFloat(seed))
      let spec = Host("main", None, children(random, ~depth=4))
      let element = toElement(spec)
      let (renderer, warnings) = logging(
        () => TestRenderer.hydrate(toMarkup(spec, ~mutation=None), element),
      )
      t
      ->expect((seed, TestRenderer.toString(renderer), warnings))
      ->Expect.toEqual((seed, direct(element), []))
      // Only empty texts, which HTML can't have, are made.
      t
      ->expect((seed, created(renderer)->Array.filter(op => op != `create ""`)))
      ->Expect.toEqual((seed, []))
    }
  })

  test("and with the markup broken at random, still end up as a direct render does", t => {
    for seed in 1 to 300 {
      let random = Random.make(Int.toFloat(seed))
      let spec = Host("main", None, children(random, ~depth=4))
      let targets = countTargets(spec)
      if targets > 1 {
        let mutation = {
          target: 1 + Random.intBelow(random, targets - 1),
          seen: 0,
          kind: Random.intBelow(random, 3),
        }
        let element = toElement(spec)
        let (renderer, warnings) = logging(
          () => TestRenderer.hydrate(toMarkup(spec, ~mutation=Some(mutation)), element),
        )
        t->expect((seed, TestRenderer.toString(renderer)))->Expect.toEqual((seed, direct(element)))
        // Something was wrong, and said so.
        t->expect((seed, Array.length(warnings) > 0))->Expect.toEqual((seed, true))
      }
    }
  })
})
