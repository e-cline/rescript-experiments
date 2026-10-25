/***
A component with classes, an animation and a fragment, using `Theme`'s variables.
`DEFINITION_SENTINEL_CARD` is in a definition, which mustn't reach the bundle.
*/
open WeftCss

let fadeIn = Css.keyframes([
  Css.frame(~at="from", {opacity: 0.}),
  Css.frame(~at="to", {opacity: 1.}),
])

let base = Css.style({padding: Px(10), borderRadius: Px(8)})

module Styles = {
  let card = Css.class({
    ...base,
    color: Var(Theme.accent),
    animationName: fadeIn,
    hover: Css.style({opacity: 0.9}),
    content: "\"DEFINITION_SENTINEL_CARD\"",
  })
}

@weft.component
let make = (~title) => <div className=Styles.card> {WeftDom.Jsx.string(title)} </div>
