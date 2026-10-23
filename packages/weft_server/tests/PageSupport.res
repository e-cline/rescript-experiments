@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/*** What the page tests share: DOM entrypoints, served from a map, and server components that wait or fail. */

let string = WeftDom.Jsx.string

module Counter = {
  @jsx.component
  let make = (~label: string) => {
    let (count, setCount) = Weft.Hooks.useState(() => 0)
    <button className="counter" onClick={_ => setCount(count => count + 1)}>
      {string(`${label}: ${Int.toString(count)}`)}
    </button>
  }
  let () = Weft.Entrypoint.mark(make, "test/Dom.res#Counter")
}

module Where = {
  /** Shows the page's URL, from `useNavigation`: the server's page, when rendered there. */
  @jsx.component
  let make = () => <code> {string(Navigation.useNavigation()->Navigation.url)} </code>
  let () = Weft.Entrypoint.mark(make, "test/Dom.res#Where")
}

module Fetches = {
  /** Asks the page to fetch while rendering, which the server's page refuses. */
  @jsx.component
  let make = () => {
    Navigation.useNavigation()->Navigation.refresh->ignore
    <p />
  }
  let () = Weft.Entrypoint.mark(make, "test/Dom.res#Fetches")
}

module Throws = {
  @jsx.component
  let make = () => JsError.throwWithMessage("the entrypoint failed")
  let () = Weft.Entrypoint.mark(make, "test/Dom.res#Throws")
}

let modules = () =>
  Testing.modules([
    (
      "test/Dom.res",
      Testing.module_([
        ("Counter", Testing.module_([("make", Testing.component(Counter.make))])),
        ("Where", Testing.module_([("make", Testing.component(Where.make))])),
        ("Fetches", Testing.module_([("make", Testing.component(Fetches.make))])),
        ("Throws", Testing.module_([("make", Testing.component(Throws.make))])),
      ]),
    ),
  ])

let assets = (): Page.assets => {
  scripts: ["/client.js"],
  preloads: [],
  styles: [],
  entrypoints: dict{"test/Dom.res": ["/assets/Dom.js"]},
  loadModule: Testing.loadModule(modules()),
}

module Later = {
  /** A server component: its children, once `ready` resolves. */
  @jsx.component
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

module ServerFails = {
  @jsx.component
  let make = (~message: string) => JsError.throwWithMessage(message)
}
