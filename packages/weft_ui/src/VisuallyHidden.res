/***
Text for assistive technology only: read out, not shown. `focusable` shows it while it has focus
(a "skip to content" link inside it).

Static: a server component can render it.
*/
open WeftCss

/** The hiding rules, to spread into a class of your own. */
let rules = Css.style({
  position: Absolute,
  width: Px(1),
  height: Px(1),
  margin: Px(-1),
  padding: Zero,
  overflow: Hidden,
  clip: "rect(0 0 0 0)",
  whiteSpace: Nowrap,
  border: "0",
})

module Styles = {
  let layer = Tokens.layer
  let hidden = Css.class(~layer, rules)
  let focusable = Css.class(
    ~layer,
    {
      ...rules,
      focusWithin: Css.style({
        position: Static,
        width: Auto,
        height: Auto,
        margin: Zero,
        overflow: Visible,
        clip: "auto",
        whiteSpace: Normal,
      }),
    },
  )
}

/** The class, for an element of your own. */
let className = Styles.hidden

@weft.component
let make = (~as_: [#span | #div]=#span, ~focusable=false, ~id=?, ~dataId=?, ~children=?) =>
  Host.element(
    (as_ :> string),
    {?id, className: focusable ? Styles.focusable : Styles.hidden, ?dataId, ?children},
  )
