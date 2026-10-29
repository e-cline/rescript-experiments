/***
What the components share for rendering their elements: a host element by tag name (for parts whose
element is a prop, `as_`), class lists with the caller's `className` last, and styles merged with
the caller's.
*/

module Jsx = WeftDom.Jsx

/** `attrs`, with `own`'s props over them: those `own` sets, not those it leaves `undefined`. */
let merge: (WeftDom.DomProps.props, unknown) => unknown = %raw(`(attrs, own) => {
  const props = {...attrs};
  for (const key in own) if (own[key] !== undefined) props[key] = own[key];
  return props;
}`)

/**
`element`, a host element, with a part's `attrs` (its escape hatch for any other DOM prop) under its
own props. A prop the part sets wins; one it leaves unset (an absent `?style`) leaves `attrs`' (a
JSX spread would write `undefined` over it). Any other element is returned as it is.
*/
let withAttrs = (attrs: WeftDom.DomProps.props, element: Weft.Element.t) =>
  switch Weft.Element.classify(element) {
  | Node({kind: Host} as node) => Weft.Element.fromNode({...node, props: merge(attrs, node.props)})
  | _ => element
  }

/** A host element, `<tag {...props}>`, with `attrs` under its props (see `withAttrs`). */
let element = (~attrs=?, tag: string, props: WeftDom.DomProps.props) => {
  let element = Jsx.Elements.jsx(tag, props)
  switch attrs {
  | Some(attrs) => withAttrs(attrs, element)
  | None => element
  }
}

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
