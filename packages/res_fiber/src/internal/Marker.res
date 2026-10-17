/***
Properties on a component function that mark it as something other than a plain component: a
context's provider (`Context.provider`) or a memoized component (`Memo.memo`). `JsxCore.jsx` reads
the mark to pick the element's kind, and the reconciler reads the rest.
*/

@get external kind: unknown => Nullable.t<string> = "$$fiberKind"
@set external setKind: ('component, string) => unit = "$$fiberKind"

@get external context: unknown => unknown = "$$fiberContext"
@set external setContext: ('component, 'context) => unit = "$$fiberContext"

@get external memoInner: unknown => unknown => Element.t = "$$fiberMemoInner"
@set external setMemoInner: ('component, 'inner) => unit = "$$fiberMemoInner"

@get external memoCompare: unknown => (unknown, unknown) => bool = "$$fiberMemoCompare"
@set external setMemoCompare: ('component, 'compare) => unit = "$$fiberMemoCompare"

let providerKind = "provider"
let memoKind = "memo"

let kindOf = (component: unknown): Element.kind =>
  switch Nullable.toOption(kind(component)) {
  | Some(kind) if kind == providerKind => Provider
  | Some(kind) if kind == memoKind => Memo
  | _ => Component
  }
