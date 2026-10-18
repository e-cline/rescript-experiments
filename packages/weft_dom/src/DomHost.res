/***
`WeftCore.HostConfig.S` for the DOM: how props become attributes, properties, styles and listeners
(see `DomProps` for the rules), and how nodes are created and arranged.

Each element keeps its latest props and one listener per event name, which looks up the current
handler when it fires: swapping a handler is a table write, not a remove and add. Handlers run
through `runEvent` (set by `Client` to the reconciler's `flushSync`), so the updates they make render
before the event returns. Afterwards a controlled `value` or `checked` the component didn't change is
put back, so an input shows its prop rather than what was typed.
*/

type container = Dom.element
type instance = Dom.element
type textInstance = Dom.text
type node = Dom.node
type props = DomProps.props
/** The names of the props that changed. */
type updatePayload = array<string>
type publicInstance = Dom.element

let instanceToNode = Dom.elementToNode
let textToNode = Dom.textToNode
let getPublicInstance = (element: Dom.element) => element

external propsToDict: props => dict<unknown> = "%identity"
external unknownToStyle: unknown => Nullable.t<DomProps.style> = "%identity"
external unknownToHandler: unknown => Nullable.t<Dom.event => unit> = "%identity"
external unknownToString: unknown => string = "%identity"
external unknownToBool: unknown => bool = "%identity"
external boolToUnknown: bool => unknown = "%identity"
external stringToUnknown: string => unknown = "%identity"
external nullableToUnknown: Nullable.t<'a> => unknown = "%identity"
external unknownToNullable: unknown => Nullable.t<unknown> = "%identity"
@val external stringify: unknown => string = "String"

/** An absent prop. */
let nothing = nullableToUnknown(Nullable.undefined)

// What the renderer keeps on each element.
@get external storedProps: Dom.element => Nullable.t<props> = "$$resFiberProps"
@set external storeProps: (Dom.element, props) => unit = "$$resFiberProps"
@get
external storedHandlers: Dom.element => Nullable.t<dict<Dom.event => unit>> = "$$resFiberHandlers"
@set external storeHandlers: (Dom.element, dict<Dom.event => unit>) => unit = "$$resFiberHandlers"
@get
external storedListeners: Dom.element => Nullable.t<dict<Dom.event => unit>> = "$$resFiberListeners"
@set
external storeListeners: (Dom.element, dict<Dom.event => unit>) => unit = "$$resFiberListeners"

/** Runs an event handler. `Client` replaces this with the reconciler's `flushSync`. */
let runEvent: ref<(unit => unit) => unit> = ref(f => f())

let tableOf = (element, get, set) =>
  switch Nullable.toOption(get(element)) {
  | Some(table) => table
  | None =>
    let table = Dict.make()
    set(element, table)
    table
  }

let isNothing = (value: unknown) => Nullable.isNullable(unknownToNullable(value))

/** Puts back a controlled `value` or `checked` an event changed but the component didn't. */
let restoreControlledState = (element: Dom.element) =>
  switch Nullable.toOption(storedProps(element)) {
  | Some(props) =>
    switch props.value {
    | Some(value) if unknownToString(Dom.getProperty(element, "value")) != value =>
      Dom.setProperty(element, "value", stringToUnknown(value))
    | _ => ()
    }
    switch props.checked {
    | Some(checked) if unknownToBool(Dom.getProperty(element, "checked")) != checked =>
      Dom.setProperty(element, "checked", boolToUnknown(checked))
    | _ => ()
    }
  | None => ()
  }

let isEventProp = (name: string) =>
  name->String.startsWith("on") &&
  String.length(name) > 2 && {
    let third = name->String.charAt(2)
    third == String.toUpperCase(third)
  }

let eventName = (prop: string) =>
  switch prop {
  | "onDoubleClick" => "dblclick"
  | _ => prop->String.slice(~start=2)->String.toLowerCase
  }

let setHandler = (element: Dom.element, event: string, handler: Nullable.t<Dom.event => unit>) => {
  let handlers = tableOf(element, storedHandlers, storeHandlers)
  let listeners = tableOf(element, storedListeners, storeListeners)
  switch (Nullable.toOption(handler), listeners->Dict.get(event)) {
  | (Some(handler), Some(_)) => handlers->Dict.set(event, handler)
  | (Some(handler), None) =>
    handlers->Dict.set(event, handler)
    let listener = domEvent => {
      switch handlers->Dict.get(event) {
      | Some(handler) => runEvent.contents(() => handler(domEvent))
      | None => ()
      }
      restoreControlledState(element)
    }
    listeners->Dict.set(event, listener)
    Dom.addEventListener(element, event, listener)
  | (None, Some(listener)) =>
    handlers->Dict.delete(event)
    listeners->Dict.delete(event)
    Dom.removeEventListener(element, event, listener)
  | (None, None) => ()
  }
}

let setStyle = (element: Dom.element, ~previous: unknown, ~next: unknown) => {
  let style = Dom.style(element)
  let apply = (name, value) =>
    if name->String.includes("-") {
      switch value {
      | Some(value) => Dom.setStyleProperty(style, name, value)
      | None => Dom.removeStyleProperty(style, name)
      }
    } else {
      Dom.setStyle(style, name, value->Option.getOr(""))
    }
  let previous = unknownToStyle(previous)->Nullable.toOption->Option.getOr(Dict.make())
  let next = unknownToStyle(next)->Nullable.toOption->Option.getOr(Dict.make())
  previous->Dict.forEachWithKey((_, name) =>
    if !(next->Dict.has(name)) {
      apply(name, None)
    }
  )
  next->Dict.forEachWithKey((value, name) =>
    if previous->Dict.get(name) != Some(value) {
      apply(name, Some(value))
    }
  )
}

let attributeName = (prop: string) =>
  switch prop {
  | "className" => "class"
  | "htmlFor" => "for"
  | "tabIndex" => "tabindex"
  | "readOnly" => "readonly"
  | "autoFocus" => "autofocus"
  | "colSpan" => "colspan"
  | name => name
  }

/** Applies one prop's change from `previous` to `next` (`undefined` meaning absent). */
let setProp = (element: Dom.element, name: string, ~previous: unknown, ~next: unknown) =>
  switch name {
  | "children" | "ref" => ()
  | "style" => setStyle(element, ~previous, ~next)
  | "value" =>
    let value = isNothing(next) ? "" : unknownToString(next)
    if unknownToString(Dom.getProperty(element, "value")) != value {
      Dom.setProperty(element, "value", stringToUnknown(value))
    }
  | "checked" =>
    let checked = !isNothing(next) && unknownToBool(next)
    if unknownToBool(Dom.getProperty(element, "checked")) != checked {
      Dom.setProperty(element, "checked", boolToUnknown(checked))
    }
  | name if isEventProp(name) => setHandler(element, eventName(name), unknownToHandler(next))
  | name =>
    let attribute = attributeName(name)
    if isNothing(next) || next === boolToUnknown(false) {
      Dom.removeAttribute(element, attribute)
    } else if next === boolToUnknown(true) {
      Dom.setAttribute(element, attribute, "")
    } else {
      Dom.setAttribute(element, attribute, stringify(next))
    }
  }

let createInstance = (~tag, ~props as _, ~container) =>
  Dom.createElement(Dom.ownerDocument(container), tag)

let createTextInstance = (text, ~container) =>
  Dom.createTextNode(Dom.ownerDocument(container), text)

let appendInitialChild = Dom.appendChild

let finalizeInitialChildren = (element, ~tag as _, ~props) => {
  propsToDict(props)->Dict.forEachWithKey((next, name) =>
    setProp(element, name, ~previous=nothing, ~next)
  )
  storeProps(element, props)
}

let prepareUpdate = (_: Dom.element, ~tag as _, ~oldProps, ~newProps) => {
  let previous = propsToDict(oldProps)
  let next = propsToDict(newProps)
  let changed = []
  let consider = name =>
    if name != "children" && !Object.is(previous->Dict.get(name), next->Dict.get(name)) {
      if !(changed->Array.includes(name)) {
        changed->Array.push(name)
      }
    }
  previous->Dict.keysToArray->Array.forEach(consider)
  next->Dict.keysToArray->Array.forEach(consider)
  // The stored props must stay current (handlers, controlled values), so always update.
  Some(changed)
}

let commitUpdate = (element, changed, ~tag as _, ~oldProps, ~newProps) => {
  let previous = propsToDict(oldProps)
  let next = propsToDict(newProps)
  changed->Array.forEach(name =>
    setProp(
      element,
      name,
      ~previous=previous->Dict.get(name)->Option.getOr(nothing),
      ~next=next->Dict.get(name)->Option.getOr(nothing),
    )
  )
  storeProps(element, newProps)
}

let commitTextUpdate = (text, ~oldText as _, ~newText) => Dom.setData(text, newText)

// Content kept mounted behind a `Suspense` fallback: hidden with an `!important` `display: none`, so
// no stylesheet shows it, and shown again with whatever `display` its `style` prop gives it.

let hideInstance = (element: Dom.element) =>
  Dom.style(element)->Dom.setStylePropertyWithPriority("display", "none", "important")

let unhideInstance = (element: Dom.element, ~props: props) =>
  switch props.style->Option.flatMap(style => style->Dict.get("display")) {
  | Some(display) => Dom.setStyleProperty(Dom.style(element), "display", display)
  | None => Dom.removeStyleProperty(Dom.style(element), "display")
  }

let hideTextInstance = (text: Dom.text) => Dom.setData(text, "")
let unhideTextInstance = (text: Dom.text, ~text as content) => Dom.setData(text, content)

let appendChild = Dom.appendChild
let insertBefore = (parent, node, ~before) => Dom.insertBefore(parent, node, before)
let removeChild = Dom.removeChild
let appendChildToContainer = Dom.appendChild
let insertInContainerBefore = (container, node, ~before) =>
  Dom.insertBefore(container, node, before)
let removeChildFromContainer = Dom.removeChild

// Moving a focused element (`insertBefore` on it or an ancestor) blurs it in browsers; put focus back
// after the commit.

let focused: ref<Nullable.t<Dom.element>> = ref(Nullable.null)

let prepareForCommit = container => focused := Dom.activeElement(Dom.ownerDocument(container))

let resetAfterCommit = container => {
  switch Nullable.toOption(focused.contents) {
  | Some(element)
    if Dom.isConnected(element) &&
    Dom.activeElement(Dom.ownerDocument(container)) !== Nullable.make(element) =>
    Dom.focus(element)
  | _ => ()
  }
  focused := Nullable.null
}
