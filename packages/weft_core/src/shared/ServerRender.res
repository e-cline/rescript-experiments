let run = HookImpl.renderOnServer
let isRunning = () => HookImpl.onServer.contents
let suspendedOn = (error: exn) =>
  switch error {
  | SuspenseImpl.Suspended(promise) => Some(promise)
  | _ => None
  }

// `Context.t` is abstract outside `Context`; it's a `ContextImpl.t`.
external contextImpl: Context.t<'value> => ContextImpl.t<unknown> = "%identity"

type contextValue = {context: ContextImpl.t<unknown>, value: unknown}
type options = {contexts: array<contextValue>, position?: array<int>, idPrefix?: string}

let contextValue = (context, value) => {
  context: contextImpl(context),
  value: Unsafe.toUnknown(value),
}

external toComponent: ('props => Element.t) => unknown => Element.t = "%identity"

let renderComponent = (component, props, options) => {
  // The values the providers above gave, for the synchronous call only: the renderer calling this
  // is asynchronous, so `ContextImpl`'s stack (one render at a time) can't hold them.
  let previous = options.contexts->Array.map(({context, value}) => {
    let before = context.currentValue
    context.currentValue = value
    (context, before)
  })
  let restore = () =>
    for index in Array.length(previous) - 1 downto 0 {
      let (context, before) = previous->Array.getUnsafe(index)
      context.currentValue = before
    }
  let previousId = HookImpl.serverId.contents
  HookImpl.serverId :=
    Some((options.idPrefix->Option.getOr("w"), options.position->Option.getOr([])))
  let restore = () => {
    HookImpl.serverId := previousId
    restore()
  }
  switch HookImpl.renderForServer(toComponent(component), Unsafe.toUnknown(props)) {
  | element =>
    restore()
    element
  | exception JsExn(thrown) =>
    restore()
    JsExn.throw(thrown)
  | exception error =>
    restore()
    throw(error)
  }
}

let isRenderingComponent = () => HookImpl.renderingForServer.contents

let providedContext = (node: Element.node) => {
  context: ContextImpl.fromUnknown(Marker.context(node.elementType)),
  value: ContextImpl.propsOf(node.props).value,
}
