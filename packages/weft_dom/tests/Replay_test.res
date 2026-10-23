@@jsxConfig({version: 4, module_: "Jsx"})

/***
Events from before hydration, in jsdom: the page's event runtime (`Html.eventRuntime`) records what's
clicked, submitted or typed on elements that haven't hydrated, and `DomHost` replays it, in order,
once they have, through the elements' own listeners.
*/

open Vitest
open DomSupport

module Hooks = Weft.Hooks

let string = Jsx.string

let tick = () => Promise.make((resolve, _) => setTimeout(() => resolve(), 0)->ignore)

let settle = async () =>
  for _ in 1 to 4 {
    await tick()
    Client.act(() => ())
  }

let deferred = (): (promise<'a>, 'a => unit) => {
  let resolve = ref(_ => ())
  let promise = Promise.make((done, _) => resolve := done)
  (promise, value => resolve.contents(value))
}

type console
@val external console: console = "console"
@get external consoleError: console => 'a => unit = "error"
@set external setConsoleError: (console, string => unit) => unit = "error"

/** Runs `f` with `console.error` quiet. */
let quietly = async (f: unit => promise<'a>) => {
  let original = console->consoleError
  console->setConsoleError(_ => ())
  let result = await f()
  console->setConsoleError(original)
  result
}

/** The events recorded and not replayed yet. */
let recorded: unit => int = %raw(`() => self.$weftEvents.length`)

/** Whether a recorded submit had its default (sending the form, leaving the page) prevented. */
let submitPrevented: unit => bool = %raw(`() =>
  self.$weftEvents.some(record => record.e.type === "submit" && record.e.defaultPrevented)`)

/** As the server sends a page: the event runtime in the head, then the shell in a root marked as having HTML. */
let serverPage = markup => {
  run(`<script>${Html.eventRuntime}</script>`)
  let container = page(markup)
  Dom.setAttribute(container, "data-weft-html", "")
  container
}

let hydrate = (container, element) =>
  Client.act(() => Client.hydrateRoot(container, element)->ignore)

let find = (container, selector) =>
  switch Nullable.toOption(Dom.querySelector(container, selector)) {
  | Some(element) => element
  | None => failwith(`nothing matches ${selector}`)
  }

@get external currentTarget: Dom.event => Nullable.t<Dom.element> = "currentTarget"
@get external targetOf: Dom.event => Dom.element = "target"
@get external checkedOf: Dom.element => bool = "checked"
@get external valueOf: Dom.element => string = "value"
@set external setValue: (Dom.element, string) => unit = "value"
@send external dispatchEvent: (Dom.element, {..}) => bool = "dispatchEvent"
@new external makeEvent: (string, {"bubbles": bool}) => {..} = "Event"
let typeInto = (element, value) => {
  setValue(element, value)
  element->dispatchEvent(makeEvent("input", {"bubbles": true}))->ignore
}
let idOf = element => Dom.getAttribute(element, "id")->Nullable.getOr("")

module Logs = {
  /** A button that logs its id, and the `currentTarget` its handler saw. */
  @weft.component
  let make = (~id: string, ~log: array<string>) =>
    <button
      id
      onClick={event =>
        log->Array.push(`${id}@${currentTarget(event)->Nullable.mapOr("none", idOf)}`)}
    >
      {string(id)}
    </button>
}

module Counter = {
  @weft.component
  let make = (~id: string) => {
    let (count, setCount) = Hooks.useState(() => 0)
    <button id onClick={_ => setCount(count => count + 1)}> {Jsx.int(count)} </button>
  }
}

module Waits = {
  @weft.component
  let make = (~promise: promise<string>, ~id: string) => <em id> {string(Hooks.use(promise))} </em>
}

module Mirror = {
  /** An input whose state follows what's typed, shown beside it. */
  @weft.component
  let make = () => {
    let (value, setValue) = Hooks.useState(() => "")
    <>
      <input id="field" value onInput={event => setValue(_ => valueOf(targetOf(event)))} />
      <b id="mirror"> {string(value)} </b>
    </>
  }
}

describe("events from before hydration", () => {
  testAsync("replays a click once its element has hydrated", async t => {
    let element = <Counter id="c" />
    let container = serverPage(await Html.renderToString(element))
    Dom.click(find(container, "#c"))
    t->expect(recorded())->Expect.toBe(1)
    t->expect(Dom.textContent(find(container, "#c")))->Expect.toBe("0")
    hydrate(container, element)
    await settle()
    t->expect(Dom.textContent(find(container, "#c")))->Expect.toBe("1")
    t->expect(recorded())->Expect.toBe(0)
    // And after that, clicks are the handler's at once.
    Client.act(() => Dom.click(find(container, "#c")))
    t->expect(Dom.textContent(find(container, "#c")))->Expect.toBe("2")
    t->expect(recorded())->Expect.toBe(0)
  })

  testAsync("gives the handler the element as the event's currentTarget", async t => {
    let log = []
    let element = <Logs id="a" log />
    let container = serverPage(await Html.renderToString(element))
    Dom.click(find(container, "#a"))
    hydrate(container, element)
    await settle()
    t->expect(log)->Expect.toEqual(["a@a"])
  })

  testAsync("records neither a link's click nor anything outside the page's root", async t => {
    let log = []
    let element =
      <a id="link" href="#somewhere" onClick={_ => log->Array.push("link")}> {string("link")} </a>
    let container = serverPage(await Html.renderToString(element))
    Dom.click(find(container, "#link"))
    let outside = Dom.createElement(Dom.document, "button")
    Dom.appendChild(Dom.body(Dom.document), Dom.elementToNode(outside))
    Dom.click(outside)
    Dom.click(container)
    t->expect(recorded())->Expect.toBe(0)
    hydrate(container, element)
    await settle()
    t->expect(log)->Expect.toEqual([])
  })

  testAsync("keeps the last input on each element, and the state follows it", async t => {
    let element = <Mirror />
    let container = serverPage(await Html.renderToString(element))
    let field = find(container, "#field")
    typeInto(field, "a")
    typeInto(field, "ab")
    typeInto(field, "abc")
    t->expect(recorded())->Expect.toBe(1)
    hydrate(container, element)
    await settle()
    t->expect(Dom.textContent(find(container, "#mirror")))->Expect.toBe("abc")
    t->expect(valueOf(field))->Expect.toBe("abc")
  })

  testAsync(
    "keeps a form from being sent, and replays the button's click and the submit",
    async t => {
      let log = []
      let element =
        <form
          id="form"
          onSubmit={event => {
            Dom.Event.preventDefault(event)
            log->Array.push("submit")
          }}
        >
          <button id="send" type_="submit" onClick={_ => log->Array.push("click")}>
            {string("Send")}
          </button>
        </form>
      let container = serverPage(await Html.renderToString(element))
      Dom.click(find(container, "#send"))
      t->expect(recorded())->Expect.toBe(2)
      t->expect(submitPrevented())->Expect.toBe(true)
      hydrate(container, element)
      await settle()
      t->expect(log)->Expect.toEqual(["click", "submit"])
    },
  )

  testAsync("ticks a checkbox once: its default isn't replayed", async t => {
    let log = []
    let element =
      <input
        id="box" type_="checkbox" onClick={event => log->Array.push(checkedOf(targetOf(event)))}
      />
    let container = serverPage(await Html.renderToString(element))
    Dom.click(find(container, "#box"))
    hydrate(container, element)
    await settle()
    t->expect(log)->Expect.toEqual([true])
    t->expect(checkedOf(find(container, "#box")))->Expect.toBe(true)
  })

  testAsync(
    "holds back what comes after an event whose element hasn't hydrated, then replays in order",
    async t => {
      let log = []
      let page = promise =>
        <div>
          <Weft.Suspense fallback={string("loading")}>
            <Waits promise id="w" />
            <Logs id="a" log />
          </Weft.Suspense>
          <Logs id="b" log />
        </div>
      let container = serverPage(await Html.renderToString(page(Promise.resolve("ready"))))
      Dom.click(find(container, "#a"))
      Dom.click(find(container, "#b"))
      // On the client, the boundary waits for its data, so `a` hasn't hydrated: `b` waits too.
      let (promise, resolve) = deferred()
      hydrate(container, page(promise))
      await settle()
      t->expect(log)->Expect.toEqual([])
      resolve("ready")
      await settle()
      t->expect(log)->Expect.toEqual(["a@a", "b@b"])
    },
  )

  testAsync("doesn't run again a handler above that saw the event when it happened", async t => {
    let log = []
    let page = promise =>
      <div id="outer" onClick={_ => log->Array.push("outer")}>
        <Weft.Suspense fallback={string("loading")}>
          <Waits promise id="w" />
          <Logs id="a" log />
        </Weft.Suspense>
      </div>
    let container = serverPage(await Html.renderToString(page(Promise.resolve("ready"))))
    let (promise, resolve) = deferred()
    hydrate(container, page(promise))
    await settle()
    // `outer` has hydrated, `a` hasn't.
    Client.act(() => Dom.click(find(container, "#a")))
    t->expect(log)->Expect.toEqual(["outer"])
    resolve("ready")
    await settle()
    t->expect(log)->Expect.toEqual(["outer", "a@a"])
  })

  testAsync("drops an event whose element hydration replaced, and goes on", async t => {
    let log = []
    let container = serverPage(
      await Html.renderToString(
        <div>
          <Weft.Suspense fallback={string("loading")}>
            <i id="gone"> {string("server")} </i>
          </Weft.Suspense>
          <Logs id="b" log />
        </div>,
      ),
    )
    Dom.click(find(container, "#gone"))
    Dom.click(find(container, "#b"))
    await quietly(
      async () => {
        // The client renders something else in the boundary: rendered on the client, `#gone` goes.
        hydrate(
          container,
          <div>
            <Weft.Suspense fallback={string("loading")}>
              <em> {string("client")} </em>
            </Weft.Suspense>
            <Logs id="b" log />
          </div>,
        )
        await settle()
      },
    )
    t->expect(log)->Expect.toEqual(["b@b"])
    t->expect(recorded())->Expect.toBe(0)
  })
})
