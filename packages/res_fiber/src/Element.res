type t

type kind =
  | Host
  | Component
  | Fragment
  | Provider
  | Memo

type node = {
  kind: kind,
  elementType: unknown,
  key: Nullable.t<string>,
  props: unknown,
}

type view =
  | Empty
  | Text(string)
  | List(array<t>)
  | Node(node)

external fromNode: node => t = "%identity"
external fromNullable: Nullable.t<'a> => t = "%identity"
external toNullable: t => Nullable.t<t> = "%identity"
external asString: t => string = "%identity"
external asArray: t => array<t> = "%identity"
external asNode: t => node = "%identity"
@val external stringify: t => string = "String"

@get
external childrenOf: unknown => t = "children"

let null: t = fromNullable(Nullable.null)

let classify = (element: t): view =>
  switch Type.typeof(element) {
  | #string => Text(asString(element))
  | #number => Text(stringify(element))
  | #object =>
    if Nullable.isNullable(toNullable(element)) {
      Empty
    } else if Array.isArray(element) {
      List(asArray(element))
    } else {
      Node(asNode(element))
    }
  | #undefined | #boolean => Empty
  | _ => JsError.throwWithMessage(`ResFiber: ${stringify(element)} is not an element`)
  }
