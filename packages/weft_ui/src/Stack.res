/***
Children in a column (or a row), a gap apart: the layout most things need.

```rescript
<Stack gap=#sm> <Heading> ... </Heading> <Text> ... </Text> </Stack>
<Stack direction=#row align=#center justify=#between wrap=true> ... </Stack>
```

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let stack = Css.class(~layer, {display: Flex, flexDirection: Column, minWidth: Zero})
  let row = Css.class(~layer, {flexDirection: Row})
  let wrap = Css.class(~layer, {flexWrap: Wrap})

  let gapNone = Css.class(~layer, {gap: Zero})
  let gapXs = Css.class(~layer, {gap: Var(Tokens.spaceXs)})
  let gapSm = Css.class(~layer, {gap: Var(Tokens.spaceSm)})
  let gapMd = Css.class(~layer, {gap: Var(Tokens.spaceMd)})
  let gapLg = Css.class(~layer, {gap: Var(Tokens.spaceLg)})
  let gapXl = Css.class(~layer, {gap: Var(Tokens.spaceXl)})
  let gapXxl = Css.class(~layer, {gap: Var(Tokens.spaceXxl)})

  let alignStart = Css.class(~layer, {alignItems: FlexStart})
  let alignCenter = Css.class(~layer, {alignItems: Center})
  let alignEnd = Css.class(~layer, {alignItems: FlexEnd})
  let alignStretch = Css.class(~layer, {alignItems: Stretch})
  let alignBaseline = Css.class(~layer, {alignItems: Baseline})

  let justifyStart = Css.class(~layer, {justifyContent: FlexStart})
  let justifyCenter = Css.class(~layer, {justifyContent: Center})
  let justifyEnd = Css.class(~layer, {justifyContent: FlexEnd})
  let justifyBetween = Css.class(~layer, {justifyContent: SpaceBetween})
}

/** A gap's class: `Stack`'s, and `Grid`'s and `List`'s through it. */
let gapClass = (gap: Variants.space) =>
  switch gap {
  | #none => Styles.gapNone
  | #xs => Styles.gapXs
  | #sm => Styles.gapSm
  | #md => Styles.gapMd
  | #lg => Styles.gapLg
  | #xl => Styles.gapXl
  | #xxl => Styles.gapXxl
  }

let alignClass = (align: Variants.align) =>
  switch align {
  | #start => Styles.alignStart
  | #center => Styles.alignCenter
  | #end => Styles.alignEnd
  | #stretch => Styles.alignStretch
  | #baseline => Styles.alignBaseline
  }

let justifyClass = justify =>
  switch justify {
  | #start => Styles.justifyStart
  | #center => Styles.justifyCenter
  | #end => Styles.justifyEnd
  | #between => Styles.justifyBetween
  }

/** A stack's classes, for an element of your own. */
let className = (
  ~direction=#column,
  ~gap: Variants.space=#md,
  ~align: option<Variants.align>=?,
  ~justify: option<[#start | #center | #end | #between]>=?,
  ~wrap=false,
  (),
) =>
  Css.cxOpt([
    Some(Styles.stack),
    direction == #row ? Some(Styles.row) : None,
    wrap ? Some(Styles.wrap) : None,
    Some(gapClass(gap)),
    align->Option.map(alignClass),
    justify->Option.map(justifyClass),
  ])

type element = [
  | #div
  | #section
  | #header
  | #footer
  | #nav
  | #main
  | #aside
  | #ul
  | #ol
  | #li
  | #form
]
external tag: element => string = "%identity"

@weft.component
let make = (
  ~as_: element=#div,
  ~direction: [#column | #row]=#column,
  ~gap: Variants.space=#md,
  ~align: option<Variants.align>=?,
  ~justify: option<[#start | #center | #end | #between]>=?,
  ~wrap=false,
  ~id=?,
  ~className as extra=?,
  ~style=?,
  ~dataId=?,
  ~ariaLabel=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=?,
) =>
  Host.element(
    tag(as_),
    {
      ...attrs,
      ?id,
      className: Host.classes([className(~direction, ~gap, ~align?, ~justify?, ~wrap, ())], extra),
      ?style,
      ?dataId,
      ?ariaLabel,
      ?children,
    },
  )
