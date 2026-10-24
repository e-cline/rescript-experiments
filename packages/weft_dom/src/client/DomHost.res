/***
`Weft.HostConfig.S` for the DOM: how props become attributes, properties, styles and listeners
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

let isEventProp = DomProps.isEventProp
let eventName = DomProps.eventName

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
    let attribute = DomProps.attributeName(name)
    switch DomProps.attributeValue(next) {
    | Some(value) => Dom.setAttribute(element, attribute, value)
    | None => Dom.removeAttribute(element, attribute)
    }
  }

let createInstance = (~tag, ~props as _, ~container) =>
  Dom.createElement(Dom.ownerDocument(container), tag)

let createTextInstance = (text, ~container) =>
  Dom.createTextNode(Dom.ownerDocument(container), text)

let appendInitialChild = Dom.appendChild

/**
A new element with `autoFocus`, to focus once the commit has put it in the page: the attribute alone
only focuses an element that's there as the page loads, as the browser parses it (the server's
HTML), not one rendered later.
*/
let autoFocused: ref<Nullable.t<Dom.element>> = ref(Nullable.null)

let finalizeInitialChildren = (element, ~tag as _, ~props: props) => {
  propsToDict(props)->Dict.forEachWithKey((next, name) =>
    setProp(element, name, ~previous=nothing, ~next)
  )
  storeProps(element, props)
  if props.autoFocus == Some(true) {
    autoFocused := Nullable.make(element)
  }
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

let commitUpdate = (element, changed, ~tag, ~oldProps, ~newProps) => {
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

  // A select's value picks one of its options, which may have changed even though the value
  // didn't (one that wasn't there when it was set may be now): set it again. Its children are
  // committed before it, so they're in place.
  if tag == "select" && !(changed->Array.includes("value")) {
    switch newProps.value {
    | Some(value) => setProp(element, "value", ~previous=nothing, ~next=stringToUnknown(value))
    | None => ()
    }
  }
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

// Replaying the events the page's event runtime (`Html.eventRuntime`) recorded before their
// elements hydrated.

/** A recorded event, and the nearest element above its target that had hydrated (which saw it). */
type recorded = {e: Dom.event, h: Nullable.t<Dom.element>}

@val @scope("globalThis") external recordedEvents: Nullable.t<array<recorded>> = "$weftEvents"
@get external eventType: Dom.event => string = "type"
@get external eventTarget: Dom.event => Dom.element = "target"
@get external cancelBubble: Dom.event => bool = "cancelBubble"
@get external parentElement: Dom.element => Nullable.t<Dom.element> = "parentElement"
let hasProps = (element: Dom.element) => Option.isSome(Nullable.toOption(storedProps(element)))

/** `event`'s `currentTarget` reads as `element` (it's `null` once the event was dispatched). */
let setCurrentTarget: (Dom.event, Nullable.t<Dom.element>) => unit = %raw(`(event, element) =>
  Object.defineProperty(event, "currentTarget", {configurable: true, value: element})`)

/**
Runs `event`'s listeners again, from its target up to `stop` (which, and whatever is above it, saw
it when it happened), as bubbling would: the listeners themselves, not a new event, so the
browser's default action (a checkbox toggling, a label's click) doesn't happen a second time.
*/
let replay = (event: Dom.event, ~stop: Nullable.t<Dom.element>) => {
  let element = ref(Some(eventTarget(event)))
  while (
    switch element.contents {
    | Some(current) => Nullable.make(current) !== stop && !cancelBubble(event)
    | None => false
    }
  ) {
    let current = Option.getUnsafe(element.contents)
    switch Nullable.toOption(storedListeners(current))->Option.flatMap(listeners =>
      listeners->Dict.get(eventType(event))
    ) {
    | Some(listener) =>
      setCurrentTarget(event, Nullable.make(current))
      listener(event)
    | None => ()
    }
    element := Nullable.toOption(parentElement(current))
  }
  setCurrentTarget(event, Nullable.null)
}

/**
Replays the recorded events whose targets have hydrated, in order: one whose target hasn't yet
holds back those after it (so "add", then "save" can't go the other way round), and one whose
target has gone (a mismatch rendered it again, or the page moved on) is dropped.
*/
let replayRecorded = () =>
  switch Nullable.toOption(recordedEvents) {
  | Some(queue) =>
    let blocked = ref(false)
    while !blocked.contents && Array.length(queue) > 0 {
      let {e, h} = Array.getUnsafe(queue, 0)
      let target = eventTarget(e)
      if !Dom.isConnected(target) {
        queue->Array.shift->ignore
      } else if !hasProps(target) {
        blocked := true
      } else {
        queue->Array.shift->ignore
        replay(e, ~stop=h)
      }
    }
  | None => ()
  }

let replayScheduled = ref(false)
@val external queueMicrotask: (unit => unit) => unit = "queueMicrotask"

/** After a commit (which may have hydrated what recorded events were waiting for), once it's done. */
let scheduleReplay = () =>
  switch Nullable.toOption(recordedEvents) {
  | Some(queue) if Array.length(queue) > 0 && !replayScheduled.contents =>
    replayScheduled := true
    queueMicrotask(() => {
      replayScheduled := false
      replayRecorded()
    })
  | _ => ()
  }

let resetAfterCommit = container => {
  switch Nullable.toOption(focused.contents) {
  | Some(element)
    if Dom.isConnected(element) &&
    Dom.activeElement(Dom.ownerDocument(container)) !== Nullable.make(element) =>
    Dom.focus(element)
  | _ => ()
  }
  focused := Nullable.null
  // A render thrown away before committing leaves one that's never attached: it isn't focused.
  switch Nullable.toOption(autoFocused.contents) {
  | Some(element) if Dom.isConnected(element) => Dom.focus(element)
  | _ => ()
  }
  autoFocused := Nullable.null
  scheduleReplay()
}

// Hydrating: rendering over the server's HTML (`Client.hydrateRoot`), adopting its nodes.

/** A node of the server's content, or a boundary's start marker. */
type hydratable = Dom.node
/** A `Suspense` boundary's start marker (a comment: `$`, `$?` or `$!`). */
type suspenseInstance = Dom.node

@get external nodeType: Dom.node => int = "nodeType"
@get external firstChild: Dom.node => Nullable.t<Dom.node> = "firstChild"
@get external nextSibling: Dom.node => Nullable.t<Dom.node> = "nextSibling"
@get external previousSibling: Dom.node => Nullable.t<Dom.node> = "previousSibling"
@get external parentNode: Dom.node => Nullable.t<Dom.element> = "parentNode"
@get external nodeData: Dom.node => string = "data"
@get external localName: Dom.node => string = "localName"
@get external nodeId: Dom.node => string = "id"
@set external setRetry: (Dom.node, unit => unit) => unit = "$weftRetry"
@send external getPropertyValue: (Dom.style, string) => string = "getPropertyValue"

external nodeToElement: Dom.node => Dom.element = "%identity"
external nodeToText: Dom.node => Dom.text = "%identity"

let elementNode = 1
let textNode = 3
let commentNode = 8

let isStartMarker = node =>
  nodeType(node) == commentNode &&
    switch nodeData(node) {
    | "$" | "$?" | "$!" => true
    | _ => false
    }
let isEndMarker = node => nodeType(node) == commentNode && nodeData(node) == "/$"

/**
A boundary's anchor: the `<template>` straight after its start marker (`id="wb:N"` while it's
pending, with the digest when it failed), which only the page's runtime uses.
*/
let isAnchor = node =>
  nodeType(node) == elementNode &&
  localName(node) == "template" &&
  previousSibling(node)->Nullable.toOption->Option.mapOr(false, isStartMarker)

/** The first hydratable node from `node` on: `None` at the end, or at a boundary's end marker. */
let rec scan = (node: Nullable.t<Dom.node>) =>
  switch node->Nullable.toOption {
  | None => None
  | Some(node) if isEndMarker(node) => None
  | Some(node) if isStartMarker(node) => Some(node)
  // A comment that only keeps two texts apart, or a boundary's anchor.
  | Some(node) if nodeType(node) == commentNode || isAnchor(node) => scan(nextSibling(node))
  | Some(node) if nodeType(node) == elementNode || nodeType(node) == textNode => Some(node)
  | Some(node) => scan(nextSibling(node))
  }

let firstHydratableChildOfContainer = (container: container) =>
  scan(firstChild(Dom.elementToNode(container)))
let firstHydratableChild = (instance: instance) => scan(firstChild(Dom.elementToNode(instance)))
let nextHydratableSibling = (node: hydratable) => scan(nextSibling(node))

let asInstance = (node: hydratable, ~tag) =>
  nodeType(node) == elementNode && localName(node) == String.toLowerCase(tag)
    ? Some(nodeToElement(node))
    : None
let asTextInstance = (node: hydratable) =>
  nodeType(node) == textNode ? Some(nodeToText(node)) : None
let asSuspenseInstance = (node: hydratable) => isStartMarker(node) ? Some(node) : None

/** A `textarea`'s text is its value, which the client sets as a property. */
let keepsOwnContent = (~tag) => tag == "textarea"

let describeHydratable = (node: hydratable) =>
  if nodeType(node) == textNode {
    `the text "${nodeData(node)}"`
  } else if nodeType(node) == commentNode {
    "a <Suspense> boundary's markers"
  } else {
    let id = nodeId(node)
    `<${localName(node)}${id == "" ? "" : ` id="${id}"`}>`
  }

/** The attributes a hydrated element has that its props wouldn't give it (development only). */
let attributeDifferences = (element: Dom.element, props: props) => {
  let differences = []
  propsToDict(props)->Dict.forEachWithKey((value, name) =>
    switch name {
    | "children" | "ref" | "key" | "value" | "checked" => ()
    | name if isEventProp(name) => ()
    | "style" =>
      let style = unknownToStyle(value)->Nullable.toOption->Option.getOr(Dict.make())
      // The browser reads a style back in its own form (`hsl(...)` as `rgb(...)`, `-0%` as `0%`):
      // the client's value is set on an element of its own and read back the same way, so the same
      // style written another way isn't a difference.
      let scratch = Dom.style(element->Dom.ownerDocument->Dom.createElement("div"))
      style->Dict.forEachWithKey((value, key) => {
        let name = DomProps.cssName(key)
        Dom.setStyleProperty(scratch, name, value)
        let expected = scratch->getPropertyValue(name)
        let actual = Dom.style(element)->getPropertyValue(name)
        if actual != expected {
          differences->Array.push(`style ${name}: "${actual}", not "${expected}"`)
        }
      })
    | name =>
      let attribute = DomProps.attributeName(name)
      let actual = Dom.getAttribute(element, attribute)->Nullable.toOption
      if actual != DomProps.attributeValue(value) {
        let show = value => value->Option.mapOr("none", value => `"${value}"`)
        differences->Array.push(
          `${attribute}: ${show(actual)}, not ${show(DomProps.attributeValue(value))}`,
        )
      }
    }
  )
  differences
}

let hydrateInstance = (element: Dom.element, ~tag as _, ~props) => {
  if Common.Env.isDev {
    switch attributeDifferences(element, props) {
    | [] => ()
    | differences =>
      Console.error(
        `WeftDom: the server's <${Dom.tagName(
            element,
          )->String.toLowerCase}> has other attributes than the client's (${differences->Array.join(
            "; ",
          )}); they're left as the server wrote them`,
      )
    }
  }
  // Handlers, which the HTML can't carry. `value` and `checked` are left as they are: the user may
  // have typed or ticked since the HTML arrived, and that's kept.
  propsToDict(props)->Dict.forEachWithKey((value, name) =>
    if isEventProp(name) {
      setHandler(element, eventName(name), unknownToHandler(value))
    }
  )
  storeProps(element, props)
}

@get external textData: Dom.text => string = "data"
let textMatches = (text: textInstance, ~text as expected) => textData(text) == expected

let suspenseState = (marker: suspenseInstance): Weft.HostConfig.suspenseState =>
  switch nodeData(marker) {
  | "$" => Complete
  | "$?" => Pending
  | _ => Failed
  }

/** A boundary's end marker. */
let endOf = (marker: suspenseInstance) => {
  let node = ref(nextSibling(marker))
  let depth = ref(0)
  let found = ref(None)
  while Option.isNone(found.contents) && Option.isSome(Nullable.toOption(node.contents)) {
    let current = Nullable.getUnsafe(node.contents)
    if isStartMarker(current) {
      depth := depth.contents + 1
    } else if isEndMarker(current) {
      if depth.contents == 0 {
        found := Some(current)
      } else {
        depth := depth.contents - 1
      }
    }
    node := nextSibling(current)
  }
  found.contents
}

let firstHydratableInSuspense = (marker: suspenseInstance) => scan(nextSibling(marker))
let nextHydratableAfterSuspense = (marker: suspenseInstance) =>
  switch endOf(marker) {
  | Some(end_) => scan(nextSibling(end_))
  | None => None
  }
let suspenseInstanceToNode = (marker: suspenseInstance): node => marker

/** The page's runtime calls the marker's `$weftRetry` once it has swapped the content in. */
let onSuspenseReady = (marker: suspenseInstance, retry) =>
  nodeData(marker) == "$?" ? setRetry(marker, retry) : retry()

let removeNode = (node: Dom.node) =>
  parentNode(node)->Nullable.toOption->Option.forEach(parent => Dom.removeChild(parent, node))

let clearSuspense = (marker: suspenseInstance) => {
  let end_ = endOf(marker)
  let node = ref(Some(marker))
  let finished = ref(false)
  while !finished.contents {
    switch node.contents {
    | Some(current) =>
      let next = nextSibling(current)->Nullable.toOption
      finished := Some(current) == end_
      removeNode(current)
      node := next
    | None => finished := true
    }
  }
}

let removeHydratable = removeNode

let clearContainer = (container: container) => Dom.setTextContent(container, "")
