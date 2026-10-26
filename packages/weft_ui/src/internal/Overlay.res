/*** What the overlays share: their state's context shape, focus, and a few DOM reads. */

module Dom = WeftDom.Dom

type ref = Weft.Ref.t<Nullable.t<Dom.element>>

let focusables = "button:not(:disabled), [href], input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex=\"-1\"])"

/** Focuses `element`'s first focusable descendant (or one with `autofocus`), or `element` itself. */
let focusFirst = (element: Dom.element) =>
  switch Dom.querySelector(element, "[autofocus]")
  ->Nullable.toOption
  ->Option.orElse(Dom.querySelector(element, focusables)->Nullable.toOption) {
  | Some(target) => Dom.focus(target)
  | None => Dom.focus(element)
  }

/** Focuses what `ref` holds, if it's still in the page. */
let focusRef = (ref: ref) =>
  ref.current->Nullable.forEach(element =>
    if Dom.isConnected(element) {
      Dom.focus(element)
    }
  )

/** Whether the focus is in `element` (or nowhere: on `<body>`), as it is when its overlay closes. */
let focusIsIn = (element: Dom.element) =>
  switch Dom.activeElement(Dom.ownerDocument(element))->Nullable.toOption {
  | Some(active) => Dom.contains(element, active) || Dom.tagName(active) == "BODY"
  | None => true
  }

/** A trigger's `anchor-name` for its popup to be placed against: a dashed ident from an ID. */
let anchorName = id => `--${id}`
