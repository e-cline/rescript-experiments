/***
The few DOM APIs the renderer, and components using it, need: hand-written bindings rather than a
dependency on a full Web API package.
*/

type node
type element
type text
type document
type event
type style

external elementToNode: element => node = "%identity"
external textToNode: text => node = "%identity"

@val external document: document = "document"
@get external body: document => element = "body"
@get external ownerDocument: element => document = "ownerDocument"
@get external activeElement: document => Nullable.t<element> = "activeElement"

@send external createElement: (document, string) => element = "createElement"
@send external createTextNode: (document, string) => text = "createTextNode"

@send external appendChild: (element, node) => unit = "appendChild"
@send external insertBefore: (element, node, node) => unit = "insertBefore"
@send external removeChild: (element, node) => unit = "removeChild"
@send external remove: element => unit = "remove"

@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external removeAttribute: (element, string) => unit = "removeAttribute"
@send external getAttribute: (element, string) => Nullable.t<string> = "getAttribute"

/** A property of an element, by name. */
@get_index
external getProperty: (element, string) => unknown = ""
@set_index external setProperty: (element, string, unknown) => unit = ""

@get external textContent: element => string = "textContent"
@set external setTextContent: (element, string) => unit = "textContent"
@get external innerHTML: element => string = "innerHTML"
@get external tagName: element => string = "tagName"
@get external isConnected: element => bool = "isConnected"
@set external setData: (text, string) => unit = "data"

@get external style: element => style = "style"
@send external setStyleProperty: (style, string, string) => unit = "setProperty"
@send external removeStyleProperty: (style, string) => unit = "removeProperty"
@send
external setStylePropertyWithPriority: (style, string, string, string) => unit = "setProperty"
@set_index external setStyle: (style, string, string) => unit = ""
@get_index external getStyle: (style, string) => string = ""

@send external addEventListener: (element, string, event => unit) => unit = "addEventListener"
@send
external removeEventListener: (element, string, event => unit) => unit = "removeEventListener"
@send external dispatchEvent: (element, event) => unit = "dispatchEvent"

@send external focus: element => unit = "focus"
@send external blur: element => unit = "blur"
@send external click: element => unit = "click"
@send external querySelector: (element, string) => Nullable.t<element> = "querySelector"
type nodeList
@send external querySelectorAllList: (element, string) => nodeList = "querySelectorAll"
@val external nodeListToArray: nodeList => array<element> = "Array.from"
/** Every element under `element` matching `selector`, in document order. */
let querySelectorAll = (element, selector) =>
  nodeListToArray(querySelectorAllList(element, selector))

/** Whether `other` is `element` or inside it. */
@send external contains: (element, element) => bool = "contains"
/** Whether `element` matches `selector`. */
@send external matches: (element, string) => bool = "matches"
/** `element`, or the nearest element above it, matching `selector`. */
@send external closest: (element, string) => Nullable.t<element> = "closest"
@get external parentElement: element => Nullable.t<element> = "parentElement"
@send external scrollIntoView: (element, {"block": string}) => unit = "scrollIntoView"

type rect = {top: float, right: float, bottom: float, left: float, width: float, height: float}
@send external getBoundingClientRect: element => rect = "getBoundingClientRect"

// Listening on the document: a popup's "click outside", a key anywhere.
@send
external addDocumentListener: (document, string, event => unit) => unit = "addEventListener"
@send
external removeDocumentListener: (document, string, event => unit) => unit = "removeEventListener"

/** A `<dialog>`'s: whether it's open, opening it as a modal (in the top layer, the page inert), or not, and closing it. */
module Dialog = {
  @get external isOpen: element => bool = "open"
  @send external showModal: element => unit = "showModal"
  @send external show: element => unit = "show"
  @send external close: element => unit = "close"
}

/** The Popover API's, on an element with a `popover` attribute. */
module Popover = {
  @send external show: element => unit = "showPopover"
  @send external hide: element => unit = "hidePopover"
  @send external toggle: element => bool = "togglePopover"
}

module Event = {
  type init = {bubbles?: bool, cancelable?: bool}

  @new external make: (string, init) => event = "Event"
  @send external preventDefault: event => unit = "preventDefault"
  @get external type_: event => string = "type"
  @get external target: event => element = "target"
  @get external currentTarget: event => element = "currentTarget"
  @send external stopPropagation: event => unit = "stopPropagation"
  @get external defaultPrevented: event => bool = "defaultPrevented"
  /** A keyboard event's `key`. */
  @get external key: event => string = "key"
  @get external shiftKey: event => bool = "shiftKey"
  @get external altKey: event => bool = "altKey"
  @get external ctrlKey: event => bool = "ctrlKey"
  @get external metaKey: event => bool = "metaKey"
  /** A focus event's other element: where focus went (`focusout`) or came from (`focusin`). */
  @get external relatedTarget: event => Nullable.t<element> = "relatedTarget"
  /** A `toggle` or `beforetoggle` event's new state: `"open"` or `"closed"`. */
  @get external newState: event => string = "newState"

  external toString: unknown => string = "%identity"
  external toBool: unknown => bool = "%identity"

  /** The `value` of the element the event happened on: an input's text. */
  let targetValue = (event: event): string => toString(getProperty(target(event), "value"))

  /** The `checked` of the element the event happened on: a checkbox's state. */
  let targetChecked = (event: event): bool => toBool(getProperty(target(event), "checked"))
}
