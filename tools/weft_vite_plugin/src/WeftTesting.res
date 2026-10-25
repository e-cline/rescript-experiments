type app
type page
type mode = Source | Build

type startOptions = {root: string, mode: string, buildDir?: string}
@module("@e-cline/weft_vite_plugin/testing")
external startJs: startOptions => promise<app> = "start"

let start = (~root, ~mode=Source, ~buildDir=?) =>
  startJs({
    root,
    mode: switch mode {
    | Source => "source"
    | Build => "build"
    },
    ?buildDir,
  })

@send external close: app => promise<unit> = "close"
@send external callServer: (app, string, string, array<JSON.t>) => promise<JSON.t> = "callServer"
@get external requests: app => array<string> = "requests"
@send external rewriteBodies: (app, string, string => string) => unit = "rewriteBodies"
@send external stopRewriting: app => unit = "stopRewriting"
@send external cookies: app => dict<string> = "cookies"
@send external clearCookies: app => unit = "clearCookies"
@get external pageRequests: page => array<string> = "requests"
@get external url: page => string = "url"

type delivery = Immediate | Manual | EveryBytes(int)

type jsDelivery = {@as("type") type_: string, size?: int}

let toJs = delivery =>
  switch delivery {
  | Immediate => {type_: "immediate"}
  | Manual => {type_: "manual"}
  | EveryBytes(size) => {type_: "everyBytes", size}
  }

type startClient = {
  loadModule: WeftServer.Decoder.loadModule,
  fetch: (string, WeftServer.Decoder.signal) => promise<WeftServer.Decoder.fetched>,
  container: WeftDom.Dom.element,
  url: string,
  signal: WeftServer.Rpc.signal,
}

type clientSide = {
  loadModule: WeftServer.Decoder.loadModule,
  start: startClient => promise<WeftServer.Navigation.t>,
  act: (unit => unit) => unit,
}

type openOptions = {
  url: string,
  container: WeftDom.Dom.element,
  delivery: jsDelivery,
  client: clientSide,
  bootstrap: bool,
}

@module("@e-cline/weft_vite_plugin/testing")
external openPage: (app, openOptions) => page = "openPage"

/** The reference map, as the browser's client has it. */
@module("virtual:weft/client-references")
external loadModule: WeftServer.Decoder.loadModule = "loadModule"

let client = {
  loadModule: id => loadModule(id),
  start: ({loadModule, fetch, container, url, signal}) =>
    WeftServer.Bootstrap.start(
      ~loadModule,
      ~fetch=(url, ~signal) => fetch(url, signal),
      ~container,
      ~url,
      ~signal,
      (),
    ),
  act: WeftDom.Client.act,
}

let open_ = (app, ~container, ~delivery=Immediate, ~bootstrap=true, url) =>
  openPage(app, {url, container, delivery: toJs(delivery), client, bootstrap})

@send external startBootstrap: page => unit = "startBootstrap"
@send external closePage: page => unit = "close"
@send external hydratedJs: (page, Nullable.t<int>) => promise<unit> = "hydrated"
let hydrated = (page, ~timeout=?) => hydratedJs(page, Nullable.fromOption(timeout))
@get external warnings: page => array<string> = "warnings"

@get external started: page => promise<WeftServer.Navigation.t> = "started"
let navigation = started
@get external shell: page => promise<string> = "shell"
@send external deliver: page => bool = "deliver"
@send external settle: page => promise<unit> = "settle"
@send external idle: page => promise<unit> = "idle"
@send external waitForJs: (page, unit => bool, Nullable.t<int>) => promise<unit> = "waitFor"
let waitFor = (page, ~timeout=?, predicate) =>
  waitForJs(page, predicate, Nullable.fromOption(timeout))
@get external pageApp: page => app = "app"
@set external setAppDelivery: (app, jsDelivery) => unit = "delivery"
let setDelivery = (page, delivery) => page->pageApp->setAppDelivery(toJs(delivery))

let navigate = async (page, url) => await (await started(page))->WeftServer.Navigation.navigate(url)
let refresh = async page => await (await started(page))->WeftServer.Navigation.refresh

@send external holdLoads: (page, ~matching: string=?) => unit = "holdLoads"
@send external releaseLoads: page => unit = "releaseLoads"
@get external loads: page => array<string> = "loads"
@get external stylesheets: page => array<string> = "stylesheets"
@send external holdStylesheets: (page, ~matching: string=?) => unit = "holdStylesheets"
@send external releaseStylesheets: page => unit = "releaseStylesheets"
@send external unstyled: page => array<string> = "unstyled"
@send external renderCount: (page, string) => int = "renderCount"

type snapshot
@send external snapshot: page => snapshot = "snapshot"
@send external removedSince: (page, snapshot) => array<string> = "removedSince"
@get external htmlNodes: page => snapshot = "htmlNodes"

@get external container: page => WeftDom.Dom.element = "container"
@send
external querySelector: (WeftDom.Dom.element, string) => Nullable.t<WeftDom.Dom.element> =
  "querySelector"
@get external textContent: WeftDom.Dom.element => string = "textContent"
@send external clickElement: WeftDom.Dom.element => unit = "click"
@set external setValue: (WeftDom.Dom.element, string) => unit = "value"
@send external dispatchEvent: (WeftDom.Dom.element, {..}) => bool = "dispatchEvent"
@new external makeEvent: (string, {"bubbles": bool}) => {..} = "Event"

@get external innerHTML: WeftDom.Dom.element => string = "innerHTML"
let html = page => page->container->innerHTML
let has = (page, selector) =>
  page->container->querySelector(selector)->Nullable.toOption->Option.isSome

let query = (page, selector) => page->container->querySelector(selector)->Nullable.toOption
let textOf = (page, selector) => query(page, selector)->Option.map(textContent)

let found = (page, selector) =>
  switch query(page, selector) {
  | Some(element) => element
  | None => JsError.throwWithMessage(`[weft] nothing on the page matches ${selector}`)
  }

let click = (page, selector) => {
  let element = found(page, selector)
  WeftDom.Client.act(() => element->clickElement)
}

let input = (page, selector, value) => {
  let element = found(page, selector)
  WeftDom.Client.act(() => {
    element->setValue(value)
    element->dispatchEvent(makeEvent("input", {"bubbles": true}))->ignore
  })
}
