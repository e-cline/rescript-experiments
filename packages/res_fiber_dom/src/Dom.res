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
@send external click: element => unit = "click"
@send external querySelector: (element, string) => Nullable.t<element> = "querySelector"
type nodeList
@send external querySelectorAllList: (element, string) => nodeList = "querySelectorAll"
@val external nodeListToArray: nodeList => array<element> = "Array.from"
/** Every element under `element` matching `selector`, in document order. */
let querySelectorAll = (element, selector) =>
  nodeListToArray(querySelectorAllList(element, selector))

module Event = {
  type init = {bubbles?: bool, cancelable?: bool}

  @new external make: (string, init) => event = "Event"
  @send external preventDefault: event => unit = "preventDefault"
  @get external type_: event => string = "type"
  @get external target: event => element = "target"
  @get external currentTarget: event => element = "currentTarget"
  /** A keyboard event's `key`. */
  @get external key: event => string = "key"

  external toString: unknown => string = "%identity"
  external toBool: unknown => bool = "%identity"

  /** The `value` of the element the event happened on: an input's text. */
  let targetValue = (event: event): string => toString(getProperty(target(event), "value"))

  /** The `checked` of the element the event happened on: a checkbox's state. */
  let targetChecked = (event: event): bool => toBool(getProperty(target(event), "checked"))
}
