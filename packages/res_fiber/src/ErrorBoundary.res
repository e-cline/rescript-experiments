type props = ErrorBoundaryImpl.props = {
  fallback: (~error: exn, ~reset: unit => unit) => Element.t,
  children: Element.t,
}

// Rendered as an `ErrorBoundaryComponent` fiber; calling it directly just renders the children.
let make: JsxCore.component<props> = props => props.children
Marker.setKind(make, Marker.errorBoundaryKind)

@get external exceptionId: exn => Nullable.t<string> = "RE_EXN_ID"

let message = (error: exn) =>
  switch error {
  | JsExn(thrown) =>
    switch JsExn.message(thrown) {
    | Some(message) => message
    | None => "Unknown error"
    }
  | _ => exceptionId(error)->Nullable.toOption->Option.getOr("Unknown exception")
  }
