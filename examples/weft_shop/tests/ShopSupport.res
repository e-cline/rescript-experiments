/***
What the scenario tests share: the app running in the harness (one per test file), pages opened in
containers of their own, and the server's controls (`ShopControl`, called in its worker).
*/

open Vitest

@val external importMetaUrl: string = "import.meta.url"
@module("node:url") external fileURLToPath: string => string = "fileURLToPath"
@module("node:path") external dirname: string => string = "dirname"

let packageRoot = dirname(dirname(fileURLToPath(importMetaUrl)))

// jsdom has no `<dialog>` methods or Popover API: weft_ui's stand-ins, for the sign-in dialog, the
// cart's drawer and the account menu.
WeftUi.Testing.installJsdomShims()

/**
Starts the app's server for the file's tests; before each, resets the server (every gate closed)
and forgets the client's cookies (a new visitor).
*/
let useApp = () => {
  let started = ref(None)
  beforeAllAsync(~timeout=60_000, async () =>
    started := Some(await WeftTesting.start(~root=packageRoot))
  )
  afterAllAsync(async () => await started.contents->Option.getOrThrow->WeftTesting.close)
  let app = () => started.contents->Option.getOrThrow(~message="the harness hasn't started")
  beforeEachAsync(async () => {
    let _ = await app()->WeftTesting.callServer("tests/ShopControl.res.js", "reset", [])
    app()->WeftTesting.clearCookies
    // The client's store outlives a page (as it would a navigation): a new page in the tests is a
    // new page load in a browser, where it starts empty.
    Signals.Atom.set(Store.cart, None)
    WeftUi.Toast.clear()
    Signals.Atom.set(Store.signInOpen, false)
  })
  app
}

module Doc = {
  type element = WeftDom.Dom.element
  @val external document: {..} = "document"
  let make = (): element => {
    let container = document["createElement"]("div")
    document["body"]["appendChild"](container)->ignore
    container
  }
  @send external remove: element => unit = "remove"
  @send external focus: element => unit = "focus"
  @get external value: element => string = "value"
  @send external querySelector: ({..}, string) => Nullable.t<element> = "querySelector"
  /** Every element in the whole document matching `selector`. */
  let all: string => array<
    element,
  > = %raw(`selector => Array.from(document.querySelectorAll(selector))`)
  /** The first element in the whole document matching `selector` (a portal's, say). */
  let find = selector => document->querySelector(selector)->Nullable.toOption
  let activeElement = (): element => document["activeElement"]
}

let containers = []

/** Removes the pages' containers, and whatever portals left in the body. */
let removeContainers = () => {
  containers->Array.forEach(Doc.remove)
  containers->Array.splice(~start=0, ~remove=Array.length(containers), ~insert=[])
  Doc.document["body"]["innerHTML"] = ""
}

afterEach(removeContainers)

/**
Opens `url` on `app`, in a container of its own (removed after the test, or when the next page
opens: a page's segments are found by id, in the whole document).
*/
let open_ = (app, ~delivery=?, ~bootstrap=?, url) => {
  removeContainers()
  let container = Doc.make()
  containers->Array.push(container)
  app->WeftTesting.open_(~container, ~delivery?, ~bootstrap?, url)
}

// The server's controls (tests/ShopControl.res, in its worker)

let control = "tests/ShopControl.res.js"
let call = (app, name, args) => app->WeftTesting.callServer(control, name, args)
let run = (app, name, args) => call(app, name, args)->Promise.thenResolve(_ => ())
let strings = json => json->JSON.Decode.array->Option.getOr([])->Array.filterMap(JSON.Decode.string)
let int = json => json->JSON.Decode.float->Option.mapOr(0, Float.toInt)
let str = s => JSON.String(s)
let num = n => JSON.Number(Int.toFloat(n))

let release = (app, gate) => run(app, "release", [str(gate)])
let releasePrefix = (app, prefix) => run(app, "releasePrefix", [str(prefix)])
let releaseAll = app => run(app, "releaseAll", [])
let fail = (app, gate, message) => run(app, "fail", [str(gate), str(message)])
let heal = (app, gate) => run(app, "heal", [str(gate)])
let hold = (app, gate) => run(app, "hold", [str(gate)])
let waiting = app => call(app, "waiting", [])->Promise.thenResolve(strings)
let abandoned = app => call(app, "abandoned", [])->Promise.thenResolve(strings)
let setStock = (app, sku, count) => run(app, "setStock", [str(sku), num(count)])
let stock = (app, sku) => call(app, "stock", [str(sku)])->Promise.thenResolve(int)
let move = (app, ~page, id, index) => run(app, "move", [str(page), str(id), num(index)])
let removeBlock = (app, ~page, id) => run(app, "remove", [str(page), str(id)])
let insertText = (app, ~page, id, index, title) =>
  run(app, "insertText", [str(page), str(id), num(index), str(title)])
let setHeroTitle = (app, ~page, title) => run(app, "setHeroTitle", [str(page), str(title)])
let setLiveEvery = (app, seconds) => run(app, "setLiveEvery", [num(seconds)])
let advanceOrder = (app, id) => run(app, "advanceOrder", [str(id)])
let orderStatus = (app, id) =>
  call(app, "orderStatus", [str(id)])->Promise.thenResolve(json =>
    json->JSON.Decode.string->Option.getOr("")
  )
let setPoll = (app, ms) => run(app, "setPoll", [num(ms)])
let sessionCount = app => call(app, "sessionCount", [])->Promise.thenResolve(int)
let wishlist = (app, name) => call(app, "wishlist", [str(name)])->Promise.thenResolve(strings)
let subscribers = app => call(app, "subscribers", [])->Promise.thenResolve(strings)

/** The client's session id (its `sid` cookie). */
let sid = app =>
  app->WeftTesting.cookies->Dict.get("sid")->Option.getOrThrow(~message="no sid cookie")

type session = {
  user: string,
  currency: string,
  count: int,
  promo: string,
  bucket: string,
  viewed: array<string>,
}

external toSession: JSON.t => session = "%identity"

/** What the server keeps for the client's session. */
let session = app => call(app, "session", [str(sid(app))])->Promise.thenResolve(toSession)
let setBucket = (app, bucket) => run(app, "setBucket", [str(sid(app)), str(bucket)])
let addToCart = (app, sku, quantity) =>
  run(app, "addToCart", [str(sid(app)), str(sku), num(quantity)])

/** The waiter for `gate` (`stock:p1#3`), the newest if there are several. */
let waiterFor = async (app, gate) =>
  (await waiting(app))
  ->Array.filter(id => id->String.startsWith(gate ++ "#"))
  ->Array.at(-1)
  ->Option.getOrThrow(~message=`nothing is waiting on ${gate}`)

/**
Waits until something is waiting on `gate` other than the waiters in `except`, and returns its
waiter's id (the newest).
*/
let nextWaiter = async (app, page, gate, ~except=[]) => {
  let rec look = async tries => {
    let found =
      (await waiting(app))
      ->Array.filter(id => id->String.startsWith(gate ++ "#") && !(except->Array.includes(id)))
      ->Array.at(-1)
    switch found {
    | Some(id) => id
    | None if tries == 0 => JsError.throwWithMessage(`nothing new is waiting on ${gate}`)
    | None =>
      await page->WeftTesting.idle
      await look(tries - 1)
    }
  }
  await look(100)
}

/** Waits until the server has recorded `waiter` as abandoned (its request cancelled). */
let abandonedSoon = async (app, page, waiter) => {
  let rec look = async tries =>
    switch ((await abandoned(app))->Array.includes(waiter), tries) {
    | (true, _) => true
    | (false, 0) => false
    | (false, _) =>
      await page->WeftTesting.idle
      await look(tries - 1)
    }
  await look(100)
}

// The page

/** The URL of what the page shows, by its navigation (where a redirect led, if one did). */
let urlOf = async page => (await page->WeftTesting.navigation)->WeftServer.Navigation.url

@val @scope("location") external pathname: string = "pathname"
@val @scope("location") external search: string = "search"
/** What the address bar shows: the history's URL, which navigating pushes (its path and query). */
let addressBar = () => pathname ++ search

let text = (page, selector) => page->WeftTesting.textOf(selector)->Option.getOr("")
let has = WeftTesting.has
/** How many elements in the document match `selector`. */
let count = selector => Doc.all(selector)->Array.length

/**
Sets a `select`'s (or an input's) value and fires `change`, as picking an option does, then lets
the page render.
*/
let change = async (page, selector, value) => {
  let element = page->WeftTesting.query(selector)->Option.getOrThrow(~message=`no ${selector}`)
  WeftDom.Dom.setProperty(element, "value", value->Obj.magic)
  WeftDom.Dom.dispatchEvent(element, WeftDom.Dom.Event.make("change", {bubbles: true}))
  await page->WeftTesting.idle
}

/** Presses `key` on the first element matching `selector` (in the whole document). */
let press = (selector, key) => {
  let element = Doc.find(selector)->Option.getOrThrow(~message=`no ${selector}`)
  let event: WeftDom.Dom.event = %raw(`(key) => new KeyboardEvent("keydown", {key, bubbles: true})`)(
    key,
  )
  WeftDom.Dom.dispatchEvent(element, event)
}

/** Clicks the first element in the whole document matching `selector` (a portal's, say). */
let clickAnywhere = selector =>
  WeftDom.Dom.click(Doc.find(selector)->Option.getOrThrow(~message=`no ${selector}`))

/** Types into the first element in the whole document matching `selector`, as an `input` event. */
let inputAnywhere = (selector, value) => {
  let element = Doc.find(selector)->Option.getOrThrow(~message=`no ${selector}`)
  WeftDom.Dom.setProperty(element, "value", value->Obj.magic)
  WeftDom.Dom.dispatchEvent(element, WeftDom.Dom.Event.make("input", {bubbles: true}))
}

/** Submits the first form in the whole document matching `selector`. */
let submitAnywhere = selector => {
  let element = Doc.find(selector)->Option.getOrThrow(~message=`no ${selector}`)
  WeftDom.Dom.dispatchEvent(
    element,
    WeftDom.Dom.Event.make("submit", {bubbles: true, cancelable: true}),
  )
}

let attribute = (page, selector, name) =>
  page
  ->WeftTesting.query(selector)
  ->Option.flatMap(element => WeftDom.Dom.getAttribute(element, name)->Nullable.toOption)

/** The `[data-id=main]` element's children, as `removedSince` names nodes: what a page's main part is made of. */
let mainChildren: WeftTesting.page => array<string> = %raw(`page => {
  const main = page.container.querySelector('[data-id=main]');
  if (main === null) return [];
  return [...main.childNodes].map((node) =>
    node.nodeType === 8 ? '<!--' + node.textContent + '-->'
      : node.nodeType === 3 ? JSON.stringify(node.textContent)
      : node.tagName.toLowerCase() + (node.dataset.id ? '[data-id=' + node.dataset.id + ']' : ''));
}`)

/**
Waits for `page` to hydrate, and fails unless it hydrated the server's HTML: none of the nodes the
HTML made replaced but those `replaced` names, and nothing warned about.
*/
let hydratedAsServed = async (page, ~replaced=[]) => {
  await page->WeftTesting.hydrated
  let unexpected =
    page
    ->WeftTesting.removedSince(page->WeftTesting.htmlNodes)
    ->Array.filter(node => !(replaced->Array.includes(node)))
  if Array.length(unexpected) > 0 {
    JsError.throwWithMessage(`hydrating replaced the HTML's ${unexpected->Array.join(", ")}`)
  }
  switch page->WeftTesting.warnings {
  | [] => ()
  | warnings => JsError.throwWithMessage(`hydrating warned: ${warnings->Array.join("\n")}`)
  }
}

/** Fails if `page` warned about anything (hydration, keys, errors). */
let noWarnings = page =>
  switch page->WeftTesting.warnings {
  | [] => ()
  | warnings => JsError.throwWithMessage(`the page warned: ${warnings->Array.join("\n")}`)
  }

/** Signs in as `name` through the header's dialog, and waits for the page to say so. */
let signIn = async (page, name) => {
  page->WeftTesting.click("[data-id=sign-in]")
  await page->WeftTesting.waitFor(() => Doc.find("[data-id=signin-dialog][open]")->Option.isSome)
  inputAnywhere("[data-id=signin-dialog] input", name)
  submitAnywhere("[data-id=signin-dialog] form")
  await page->WeftTesting.waitFor(() =>
    text(page, "[data-id=account-menu]")->String.includes(`Hi, ${name}`)
  )
}
