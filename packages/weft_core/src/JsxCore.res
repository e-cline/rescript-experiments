type element = Element.t
type component<'props> = 'props => element
type componentLike<'props, 'return> = 'props => 'return

external component: componentLike<'props, element> => component<'props> = "%identity"
external componentToUnknown: component<'props> => unknown = "%identity"

type fragmentProps = {children?: element}

let jsxFragment: component<fragmentProps> = _ =>
  Errors.fail(
    11,
    Common.Env.isDev
      ? "WeftCore: jsxFragment is a marker for <>...</>, not a component to call"
      : "",
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

@get external rawChildren: 'props => unknown = "children"

// The transform calls `jsxs` only for two or more children, written out: `children` is the array it
// built. A development build records it, so the reconciler doesn't warn that they have no keys.
let markStaticChildren = (props: 'props) =>
  if Common.Env.isDev {
    let children = rawChildren(props)
    if Array.isArray(children) {
      KeyWarnings.markStatic(Unsafe.fromUnknown(children))
    }
  }

let jsx = (component, props) => make(component, props, Nullable.null)
let jsxs = (component, props) => {
  markStaticChildren(props)
  jsx(component, props)
}
let jsxKeyed = (component, props, ~key=?, ()) => make(component, props, toKey(key))
let jsxsKeyed = (component, props, ~key=?, ()) => {
  markStaticChildren(props)
  jsxKeyed(component, props, ~key?, ())
}

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
let hostJsxs = (tag, props) => {
  markStaticChildren(props)
  hostJsx(tag, props)
}
let hostJsxsKeyed = (tag, props, ~key=?, ()) => {
  markStaticChildren(props)
  hostJsxKeyed(tag, props, ~key?, ())
}
