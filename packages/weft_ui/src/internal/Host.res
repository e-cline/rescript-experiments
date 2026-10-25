/***
What the components share for rendering their elements: a host element by tag name (for parts whose
element is a prop, `as_`), class lists with the caller's `className` last, and styles merged with
the caller's.
*/

/** A host element, `<tag {...props}>`. */
let element = (tag: string, props: WeftDom.DomProps.props) => WeftDom.Jsx.Elements.jsx(tag, props)

/** `classes`, then the caller's `className`, as one class list. */
let classes = (classes: array<string>, className: option<string>) =>
  WeftCss.Css.cx(className->Option.mapOr(classes, className => [...classes, className]))

/** The caller's `style`, with `own` (a component's custom properties) under it: the caller's win. */
let style = (own: dict<string>, style: option<dict<string>>) =>
  switch style {
  | None => own
  | Some(style) => Dict.assign(Dict.copy(own), style)
  }

/** `"true"` or `"false"`, as ARIA's boolean attributes take them. */
let ariaBool = (value: bool) => value ? "true" : "false"
