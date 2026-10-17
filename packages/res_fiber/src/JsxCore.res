type element = Element.t
type component<'props> = 'props => element
type componentLike<'props, 'return> = 'props => 'return

external component: componentLike<'props, element> => component<'props> = "%identity"
external componentToUnknown: component<'props> => unknown = "%identity"

type fragmentProps = {children?: element}

let jsxFragment: component<fragmentProps> = _ =>
  JsError.throwWithMessage(
    "ResFiber: jsxFragment is a marker for <>...</>, not a component to call",
  )

let fragmentType = componentToUnknown(jsxFragment)

module Fragment = {
  type props<'children> = {children?: 'children}
  external fromFragment: component<fragmentProps> => component<props<element>> = "%identity"
  let make = fromFragment(jsxFragment)
}

let toKey = (key: option<string>): Nullable.t<string> =>
  switch key {
  | Some(key) => Nullable.make(key)
  | None => Nullable.null
  }

let make = (component: component<'props>, props: 'props, key: Nullable.t<string>): element => {
  let elementType = componentToUnknown(component)
  Element.fromNode({
    kind: elementType === fragmentType ? Fragment : Marker.kindOf(elementType),
    elementType,
    key,
    props: Unsafe.toUnknown(props),
  })
}

let jsx = (component, props) => make(component, props, Nullable.null)
let jsxs = jsx
let jsxKeyed = (component, props, ~key=?, ()) => make(component, props, toKey(key))
let jsxsKeyed = jsxKeyed

external array: array<element> => element = "%identity"
let null = Element.null
external string: string => element = "%identity"
external int: int => element = "%identity"
external float: float => element = "%identity"
external someElement: element => option<element> = "%identity"

let makeHost = (tag: string, props: 'props, key: Nullable.t<string>): element =>
  Element.fromNode({
    kind: Host,
    elementType: Unsafe.toUnknown(tag),
    key,
    props: Unsafe.toUnknown(props),
  })

let hostJsx = (tag, props) => makeHost(tag, props, Nullable.null)
let hostJsxKeyed = (tag, props, ~key=?, ()) => makeHost(tag, props, toKey(key))
