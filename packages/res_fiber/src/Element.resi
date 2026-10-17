/***
What a component returns: a description of the UI, which the reconciler turns into fibers and the
host renderer turns into real nodes.

`t` is abstract. Elements are made by a JSX module (see `JsxCore`); at runtime one is `null` or
`undefined` (nothing), a string or number (text), a JS array (a list of children), or a `node`
record. `classify` is the one place that inspects which, and is exposed for renderers and tests.
*/

/** An element. */
type t

/** What a `node` element creates. */
type kind =
  /** A host element such as `<div>`: `elementType` is the tag name. */
  | Host
  /** A function component: `elementType` is its `make` function. */
  | Component
  /** `<> ... </>`: its children with no node of its own. */
  | Fragment
  /** A context provider: `elementType` is the context's `Context.provider`. */
  | Provider
  /** A component wrapped by `Memo.memo`: `elementType` is the wrapper. */
  | Memo
  /** An `ErrorBoundary`: `elementType` is `ErrorBoundary.make`. */
  | ErrorBoundary
  /** `Portal.create`: its children, rendered into another container (`elementType`). */
  | Portal
  /** A `Suspense` boundary: `elementType` is `Suspense.make`. */
  | Suspense

/**
An element that isn't text or a list. `props` is the record the JSX transform built (for host and
component elements), or a `{children}` record (for fragments). `key` is `null` unless one was given.
*/
type node = {
  kind: kind,
  elementType: unknown,
  key: Nullable.t<string>,
  props: unknown,
}

/** An element, by what it is at runtime. */
type view =
  | Empty
  | Text(string)
  | List(array<t>)
  | Node(node)

/** What `element` is at runtime. Throws if it isn't an element at all (a function, say). */
let classify: t => view

/** The element that renders nothing. */
let null: t

external fromNode: node => t = "%identity"

/** The `children` field of a props record, or `undefined` (which renders nothing) if it has none. */
@get
external childrenOf: unknown => t = "children"
