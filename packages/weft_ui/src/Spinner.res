/***
Something's working. With `announce` (the default), it's a `status` whose `label` ("Loading", or
yours) is read out; without, only a picture, for inside something that says so itself (a busy
button).

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let turn = Css.keyframes(~layer, [Css.frame(~at="to", {transform: "rotate(360deg)"})])
  let spinner = Css.class(
    ~layer,
    {
      display: InlineBlock,
      flexShrink: 0.,
      borderRadius: Var(Tokens.radiusFull),
      border: "2px solid currentColor",
      borderColor: Raw("currentColor transparent currentColor currentColor"),
      animationName: turn,
      animationDuration: Tokens.value(Tokens.durationSpin),
      animationTimingFunction: "linear",
      animationIterationCount: "infinite",
      verticalAlign: "middle",
    },
  )
  let sm = Css.class(~layer, {width: Em(1.), height: Em(1.)})
  let md = Css.class(~layer, {width: Px(20), height: Px(20)})
  let lg = Css.class(~layer, {width: Px(32), height: Px(32), borderWidth: Px(3)})
  let status = Css.class(~layer, {display: InlineFlex, alignItems: Center})
}

let picture = (~size: Variants.size, ~className=?) =>
  <span
    className={Host.classes(
      [
        Styles.spinner,
        switch size {
        | #sm => Styles.sm
        | #md => Styles.md
        | #lg => Styles.lg
        },
      ],
      className,
    )}
    ariaHidden="true"
  />

@weft.component
let make = (
  ~size: Variants.size=#md,
  ~label="Loading",
  ~announce=true,
  ~id=?,
  ~className=?,
  ~dataId=?,
) =>
  announce
    ? <span ?id className=Styles.status role="status" ?dataId>
        {picture(~size, ~className?)}
        <VisuallyHidden> {WeftDom.Jsx.string(label)} </VisuallyHidden>
      </span>
    : <span ?id className=Styles.status ?dataId> {picture(~size, ~className?)} </span>
