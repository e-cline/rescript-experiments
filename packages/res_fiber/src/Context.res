type t<'value> = ContextImpl.t<'value>

type providerProps<'value> = ContextImpl.providerProps<'value> = {
  value: 'value,
  children: Element.t,
}

external providerToUnknown: JsxCore.component<providerProps<'value>> => unknown = "%identity"
external unknownToProvider: unknown => JsxCore.component<providerProps<'value>> = "%identity"

let make = (defaultValue: 'value): t<'value> => {
  let context: t<'value> = {
    currentValue: defaultValue,
    defaultValue,
    provider: Unsafe.nothing,
  }
  // Rendered as a `ContextProvider` fiber, never called; calling it directly renders its children.
  let provider: JsxCore.component<providerProps<'value>> = props => props.children
  Marker.setKind(provider, Marker.providerKind)
  Marker.setContext(provider, context)
  context.provider = providerToUnknown(provider)
  context
}

let provider = (context: t<'value>) => unknownToProvider(context.provider)
