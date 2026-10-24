@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/***
What the tests share: server components and entrypoints written the way `ppx_weft` compiles them
(async ones return a `Lazy` element; entrypoints are marked with an id), the modules that serve the
entrypoints, and helpers for running a payload from `Render` through `Client` into a
`TestRenderer`.
*/

module TestRenderer = Weft.TestRenderer
module TestJsx = Weft.TestJsx
module Deferred = Weft.Deferred

let text = TestJsx.string

/** Lets the renderer flush, promises settle and the TestRenderer render, a few times over. */
let settle = async () =>
  for _ in 1 to 6 {
    await Testing.tick()
    TestRenderer.act(() => ())
    Weft.TestScheduler.flushAll()
  }

/** A payload's rows, one string each, without the newlines. */
let rows = (payload: string) => payload->String.split("\n")->Array.filter(row => row != "")

// Entrypoints

/** Each `Counter`'s state setter, by label, so tests can bump it. */
let setCounts: dict<(int => int) => unit> = Dict.make()
/** How many times each `Counter` has rendered, by label. */
let renders: dict<int> = Dict.make()

let bump = label => {
  let setCount = setCounts->Dict.getUnsafe(label)
  TestRenderer.act(() => setCount(count => count + 1))
}
let rendersOf = label => renders->Dict.get(label)->Option.getOr(0)
let resetCounts = () => {
  setCounts->Dict.keysToArray->Array.forEach(key => setCounts->Dict.delete(key))
  renders->Dict.keysToArray->Array.forEach(key => renders->Dict.delete(key))
}

module Counter = {
  /** A counter with state, showing its label, its count and any children it's given. */
  @weft.component
  let make = (~label: string, ~note: option<string>=?, ~children: option<Weft.Element.t>=?) => {
    let (count, setCount) = Weft.Hooks.useState(() => 0)
    setCounts->Dict.set(label, setCount)
    renders->Dict.set(label, rendersOf(label) + 1)
    let content =
      <>
        {text(`${label}:${Int.toString(count)}`)}
        {children->Option.getOr(TestJsx.null)}
      </>
    // Without a note, no `title` at all (the TestRenderer would print an undefined one).
    switch note {
    | Some(note) => <b id=label title=note> content </b>
    | None => <b id=label> content </b>
    }
  }
  let () = Weft.Entrypoint.mark(make, "test/Entrypoints.res#Counter")
}

external toUnknown: 'a => unknown = "%identity"

/** The props each `Probe` received last, by `name`. */
let received: dict<unknown> = Dict.make()

module Probe = {
  /** Records the props it gets, for tests of how values travel. */
  @weft.component
  let make = (~name: string, ~value: 'value) => {
    received->Dict.set(name, toUnknown(value))
    <i id=name />
  }
  let () = Weft.Entrypoint.mark(make, "test/Entrypoints.res#Probe")
}

module Reader = {
  /** Reads a promise prop with `Hooks.use`. */
  @weft.component
  let make = (~id: string, ~promise: promise<string>) => <u id> {text(Weft.Hooks.use(promise))} </u>
  let () = Weft.Entrypoint.mark(make, "test/Entrypoints.res#Reader")
}

module Guard = {
  /** An error boundary, which has to be an entrypoint (its fallback is a function). */
  @weft.component
  let make = (~children: Weft.Element.t) =>
    <Weft.ErrorBoundary
      fallback={(~error, ~reset as _) =>
        <p id="error"> {text(Weft.ErrorBoundary.message(error))} </p>}
    >
      children
    </Weft.ErrorBoundary>
  let () = Weft.Entrypoint.mark(make, "test/Entrypoints.res#Guard")
}

module Inner = {
  @weft.component
  let make = (~label: string) => <s id=label> {text(label)} </s>
  let () = Weft.Entrypoint.mark(make, "test/Other.res#")
}

/** Each `Refetching`'s `refetch`, by `src`. */
let refetchers: dict<(~url: string=?) => promise<unit>> = Dict.make()

module Refetching = {
  /**
  Refetches its children, from `src`, with `Navigation.useRefetchable`: says whether it's pending
  (its `title`), and keeps its `refetch` where tests can call it.
  */
  @weft.component
  let make = (~id: string, ~src: string, ~children: Weft.Element.t) => {
    let {element, refetch, isPending} = Navigation.useRefetchable(~src, children)
    refetchers->Dict.set(src, refetch)
    <div id title={isPending ? "pending" : "idle"}> element </div>
  }
  let () = Weft.Entrypoint.mark(make, "test/Entrypoints.res#Refetching")
}

let theme = Weft.Context.make("plain")

module Themed = {
  /** Provides a theme to its children, as an entrypoint can. */
  @weft.component
  let make = (~value: string, ~children: Weft.Element.t) =>
    Weft.JsxCore.jsx(Weft.Context.provider(theme), {value, children})
  let () = Weft.Entrypoint.mark(make, "test/Entrypoints.res#Themed")
}

module ThemeReader = {
  /** Shows the theme it gets from above. */
  @weft.component
  let make = (~id: string) => <q id> {text(Weft.Hooks.useContext(theme))} </q>
  let () = Weft.Entrypoint.mark(make, "test/Entrypoints.res#ThemeReader")
}

let entrypointFile = Testing.module_([
  ("Counter", Testing.module_([("make", Testing.component(Counter.make))])),
  ("Probe", Testing.module_([("make", Testing.component(Probe.make))])),
  ("Reader", Testing.module_([("make", Testing.component(Reader.make))])),
  ("Guard", Testing.module_([("make", Testing.component(Guard.make))])),
  ("Refetching", Testing.module_([("make", Testing.component(Refetching.make))])),
  ("Themed", Testing.module_([("make", Testing.component(Themed.make))])),
  ("ThemeReader", Testing.module_([("make", Testing.component(ThemeReader.make))])),
])

let makeModules = () =>
  Testing.modules([
    ("test/Entrypoints.res", entrypointFile),
    ("test/Other.res", Testing.module_([("make", Testing.component(Inner.make))])),
  ])

// Server components

module Async = {
  /** An async server component (as the PPX compiles one): its children, once `ready` resolves. */
  @weft.component
  let make = (~ready: promise<unit>, ~children: Weft.Element.t) =>
    Weft.Lazy.fromPromise(
      (
        async () => {
          await ready
          children
        }
      )(),
    )
}

module Fails = {
  /** A server component that throws. */
  @weft.component
  let make = (~message: string) => JsError.throwWithMessage(message)
}

module Uses = {
  /** A server component that reads a promise with `Hooks.use`. */
  @weft.component
  let make = (~promise: promise<string>) => <em> {text(Weft.Hooks.use(promise))} </em>
}

module Wrap = {
  /** A server component that renders its children in a `<div>`. */
  @weft.component
  let make = (~id: string, ~children: Weft.Element.t) => <div id> children </div>
}

module WrapAgain = {
  /** The same output as `Wrap`, from another component. */
  @weft.component
  let make = (~id: string, ~children: Weft.Element.t) => <div id> children </div>
}

let loading = <i id="loading"> {text("loading")} </i>

// Running a payload

/** A client for the test entrypoints. */
let makeClient = (~modules=makeModules()) =>
  Decoder.make(~loadModule=Testing.loadModule(modules), ~fetch=(_, ~signal as _) =>
    JsError.throwWithMessage("this test client doesn't fetch")
  )

/** `element`, rendered on the server and decoded by `client`, with everything delivered at once. */
let roundTrip = (~client=makeClient(), ~chunking=?, element) =>
  client->Decoder.fromStream(Testing.stream(Testing.pipe(Render.toStream(element), ~chunking?)))

/** `element` rendered straight into a TestRenderer, for comparing with a round trip's. */
let renderDirectly = element => {
  let renderer = TestRenderer.create()
  TestRenderer.render(renderer, element)
  TestRenderer.toString(renderer)
}

/** The decoded `element`, rendered into a new TestRenderer, once everything has arrived. */
let renderRoundTrip = async (~client=?, ~chunking=?, element) => {
  let decoded = await roundTrip(~client?, ~chunking?, element)
  let renderer = TestRenderer.create()
  TestRenderer.render(renderer, decoded)
  await settle()
  TestRenderer.toString(renderer)
}

// An in-process server

/** A request a `serve` client made: its URL, and the server's stream on its way back. */
type served = {url: string, pipe: Testing.pipe}

/**
A `fetch` answering each URL with `route(url)`, rendered by the server, through a pipe delivered as
`delivery(url)` says; and the requests it has served, in order.
*/
let serve = (~delivery=_ => Testing.Immediate, route: string => Weft.Element.t) => {
  let served = []
  let fetch = (url, ~signal) => {
    let pipe = Testing.pipe(Render.toStream(route(url), ~signal), ~delivery=delivery(url))
    served->Array.push({url, pipe})
    Promise.resolve({Decoder.stream: Testing.stream(pipe)})
  }
  (fetch, served)
}
