/*** What the components' tests share: rendering in jsdom, finding elements, and events. */

module Dom = WeftDom.Dom

let text = WeftDom.Jsx.string

/** `element`, rendered into a fresh container in the document. */
let mount = (element: Weft.Element.t) => {
  let container = Dom.createElement(Dom.document, "div")
  Dom.appendChild(Dom.body(Dom.document), Dom.elementToNode(container))
  let root = WeftDom.Client.createRoot(container)
  WeftDom.Client.act(() => WeftDom.Client.render(root, element))
  container
}

let find = (container, selector) =>
  switch Nullable.toOption(Dom.querySelector(container, selector)) {
  | Some(element) => element
  | None => failwith(`nothing matches ${selector}`)
  }

let findAll = Dom.querySelectorAll

let attribute = (element, name) => Dom.getAttribute(element, name)->Nullable.toOption

/** `element`'s classes. */
let classes = element => attribute(element, "class")->Option.getOr("")->String.split(" ")

let has = (element, className) => classes(element)->Array.includes(className)

let click = element => WeftDom.Client.act(() => Dom.click(element))

/** The server's payload for `element`, as a server component's output is sent, and its errors. */
let serverRender = async (element: Weft.Element.t) => {
  let errors = []
  let payload = await WeftServer.Testing.readAll(
    WeftServer.Render.toStream(element, ~onError=error => {
      errors->Array.push(error)
      None
    }),
  )
  (payload, errors)
}

/** A key pressed on `element` (a `keydown` that bubbles and can be cancelled). */
let keyDown = (element, key) => {
  let event: Dom.event = %raw(`(key) => new KeyboardEvent("keydown", {key, bubbles: true, cancelable: true})`)(
    key,
  )
  WeftDom.Client.act(() => Dom.dispatchEvent(element, event))
  event
}

/** Types `text` into an input: sets its value and fires `input`, as a keystroke would. */
let typeInto = (input, text) =>
  WeftDom.Client.act(() => {
    Dom.setProperty(input, "value", Obj.magic(text))
    Dom.dispatchEvent(input, Dom.Event.make("input", {bubbles: true}))
  })

/** Fires `blur` on `element`, as the focus leaving it would. */
let blur = element =>
  WeftDom.Client.act(() => Dom.dispatchEvent(element, Dom.Event.make("blur", {})))

let focus = element => WeftDom.Client.act(() => Dom.focus(element))

let activeElement = () => Dom.activeElement(Dom.document)->Nullable.toOption

external toString: unknown => string = "%identity"
external toBool: unknown => bool = "%identity"
let property = (element, name) => Dom.getProperty(element, name)
