/***
What a value is at runtime, for the renderer's encoder: the checks ReScript's types can't make,
since props are erased into `unknown` inside elements.
*/

external toUnknown: 'a => unknown = "%identity"
external fromUnknown: unknown => 'a = "%identity"

let isNull = (value: unknown) => Nullable.isNullable(fromUnknown(value))

@scope("Object") @val external prototypeOf: unknown => Nullable.t<unknown> = "getPrototypeOf"
let objectPrototype: unknown = %raw(`Object.prototype`)

/** An object made by `{...}` (or with no prototype): what ReScript records, variants and dicts are. */
let isPlainObject = (value: unknown) =>
  switch prototypeOf(value)->Nullable.toOption {
  | None => true
  | Some(prototype) => prototype === objectPrototype
  }

let isThenable: unknown => bool = %raw(`value => value != null && typeof value.then === "function"`)
let isDate: unknown => bool = %raw(`value => value instanceof Date`)

@scope("Object") @val external keys: unknown => array<string> = "keys"
@get_index external get: (unknown, string) => unknown = ""

/**
Sets `name` as an own property, whatever it is: assigning `__proto__` would change the object's
prototype instead. Anything rebuilding an object from data (the payload's, an RPC's) sets its fields
with this.
*/
let defineField: (dict<'a>, string, 'a) => unit = %raw(`(object, name, value) => {
  Object.defineProperty(object, name, {value, writable: true, enumerable: true, configurable: true})
}`)

let elementKinds = [
  "Host",
  "Component",
  "Fragment",
  "Provider",
  "Memo",
  "ErrorBoundary",
  "Portal",
  "Suspense",
  "Offscreen",
  "Lazy",
]

/**
Whether `value` is an element node (`Weft.Element.node`): a plain object with exactly its four
fields, and a `kind` that's one of `Element.kind`'s. A record of the same shape would be taken for
one; that's the price of elements having no brand.
*/
let isElementNode = (value: unknown) =>
  isPlainObject(value) && {
    let fields = keys(value)
    Array.length(fields) == 4 &&
    ["kind", "elementType", "key", "props"]->Array.every(field => fields->Array.includes(field)) &&
    switch Type.typeof(get(value, "kind")) {
    | #string => elementKinds->Array.includes(fromUnknown(get(value, "kind")))
    | _ => false
    }
  }

@get external functionName: unknown => string = "name"

/** A component's name, for messages: its `make` function's, which the compiler names after its module. */
let componentName = (make: unknown) =>
  switch functionName(make) {
  | "" => "an anonymous component"
  | name => name->String.replaceAll("$", ".")
  }

@get external exceptionId: exn => Nullable.t<string> = "RE_EXN_ID"

/** What went wrong, as text. */
let describeError = (error: exn) =>
  switch error {
  | JsExn(error) => JsExn.message(error)->Option.getOr("an error")
  | _ =>
    switch exceptionId(error)->Nullable.toOption {
    | Some(id) => `the ReScript exception ${id}`
    | None => "an error"
    }
  }
