/***
A line between things: a `separator` to assistive technology, or, `decorative`, only to the eye.

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let separator = Css.class(~layer, {flexShrink: 0., backgroundColor: Var(Tokens.border)})
  let horizontal = Css.class(~layer, {blockSize: Px(1), inlineSize: Pct(100.)})
  let vertical = Css.class(~layer, {inlineSize: Px(1), alignSelf: Stretch})
}

@weft.component
let make = (
  ~orientation: Variants.orientation=#horizontal,
  ~decorative=false,
  ~id=?,
  ~className=?,
  ~style=?,
  ~dataId=?,
) =>
  <div
    ?id
    className={Host.classes(
      [Styles.separator, orientation == #vertical ? Styles.vertical : Styles.horizontal],
      className,
    )}
    ?style
    ?dataId
    role={decorative ? "none" : "separator"}
    ariaOrientation=?{!decorative && orientation == #vertical ? Some("vertical") : None}
    dataOrientation={Variants.orientationName(orientation)}
  />
