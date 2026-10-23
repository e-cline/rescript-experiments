/***
What the scenario tests share: the app running in the harness (one per test file), pages opened in
containers of their own, and the fake database's controls, called in the server's worker.
*/

open Vitest

@val external importMetaUrl: string = "import.meta.url"
@module("node:url") external fileURLToPath: string => string = "fileURLToPath"
@module("node:path") external dirname: string => string = "dirname"

let packageRoot = dirname(dirname(fileURLToPath(importMetaUrl)))

/** Starts the app's server for the file's tests, and resets the database before each. */
let useApp = () => {
  let started = ref(None)
  beforeAllAsync(~timeout=60_000, async () =>
    started := Some(await WeftTesting.start(~root=packageRoot))
  )
  afterAllAsync(async () => await started.contents->Option.getOrThrow->WeftTesting.close)
  () => started.contents->Option.getOrThrow(~message="the harness hasn't started")
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
  @send external setSelectionRange: (element, int, int) => unit = "setSelectionRange"
  @get external selectionStart: element => int = "selectionStart"
  @get external selectionEnd: element => int = "selectionEnd"
  @get external value: element => string = "value"
  let activeElement = (): element => document["activeElement"]
}

let containers = []

let removeContainers = () => {
  containers->Array.forEach(Doc.remove)
  containers->Array.splice(~start=0, ~remove=Array.length(containers), ~insert=[])
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

// The fake database (tests/FakeDbControl.res, in the server's worker)

let control = "tests/FakeDbControl.res.js"
let strings = json => json->JSON.Decode.array->Option.getOr([])->Array.filterMap(JSON.Decode.string)

let reset = app => app->WeftTesting.callServer(control, "reset", [])->Promise.thenResolve(_ => ())
let release = (app, gate) =>
  app->WeftTesting.callServer(control, "release", [JSON.String(gate)])->Promise.thenResolve(_ => ())
let waiting = app =>
  app->WeftTesting.callServer(control, "waiting", [])->Promise.thenResolve(strings)
let abandoned = app =>
  app->WeftTesting.callServer(control, "abandoned", [])->Promise.thenResolve(strings)
let addComment = (app, ~noteId, ~author, ~text) =>
  app
  ->WeftTesting.callServer(
    control,
    "addComment",
    [JSON.String(noteId), JSON.String(author), JSON.String(text)],
  )
  ->Promise.thenResolve(_ => ())
let editComment = (app, ~noteId, ~commentId, ~text) =>
  app
  ->WeftTesting.callServer(
    control,
    "editComment",
    [JSON.String(noteId), JSON.String(commentId), JSON.String(text)],
  )
  ->Promise.thenResolve(_ => ())
let setLikes = (app, ~noteId, ~likes) =>
  app
  ->WeftTesting.callServer(
    control,
    "setLikes",
    [JSON.String(noteId), JSON.Number(Int.toFloat(likes))],
  )
  ->Promise.thenResolve(_ => ())

/** The waiter for `gate` (`comments:1#3`), the newest if there are several. */
let waiterFor = async (app, gate) =>
  (await waiting(app))
  ->Array.filter(id => id->String.startsWith(gate ++ "#"))
  ->Array.at(-1)
  ->Option.getOrThrow(~message=`nothing is waiting on ${gate}`)

let text = (page, selector) => page->WeftTesting.textOf(selector)->Option.getOr("")
let has = WeftTesting.has
let likes = (app, ~noteId) =>
  app
  ->WeftTesting.callServer(control, "likes", [JSON.String(noteId)])
  ->Promise.thenResolve(json => json->JSON.Decode.float->Option.mapOr(0, Float.toInt))
let commentCount = (app, ~noteId) =>
  app
  ->WeftTesting.callServer(control, "commentCount", [JSON.String(noteId)])
  ->Promise.thenResolve(json => json->JSON.Decode.float->Option.mapOr(0, Float.toInt))
let removeNote = (app, ~noteId) =>
  app
  ->WeftTesting.callServer(control, "removeNote", [JSON.String(noteId)])
  ->Promise.thenResolve(_ => ())

// Hydration

/**
What hydrating a note's page renders on the client: the boundary around the error box (the server's
error is thrown again there, for the box to catch), if the HTML had it by then.
*/
let errorBoxPart = [
  "<!--$-->",
  "<!--$!-->",
  "template",
  "p#broken-loading",
  `"…"`,
  "<!--/$-->",
  "<!--/$-->",
]

/**
Waits for `page` to hydrate, and fails unless it hydrated the server's HTML: none of the nodes the
HTML made replaced but those `replaced` names (what's rendered on the client instead), and nothing
warned about.
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

/**
Turns the test's clock (the browser's, not the server's: that's in its worker) back `days` days,
until the function it returns is called.
*/
let turnClockBack: int => unit => unit = %raw(`days => {
  const now = Date.now;
  Date.now = () => now() - days * 86400000;
  return () => {
    Date.now = now;
  };
}`)

/** The date `Today` shows, by the test's clock. */
let today = () => Date.fromTime(Date.now())->Date.toISOString->String.slice(~start=0, ~end=10)
