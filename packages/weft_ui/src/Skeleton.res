/***
A placeholder in the shape of what's coming, while it loads. It's only a picture (`aria-hidden`):
mark the region that's loading busy (`ariaBusy="true"`), or give it a `Spinner`'s label, for
assistive technology.

```rescript
<Skeleton lines=3 />
<Skeleton shape=#rect height="160px" />
```

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let pulse = Css.keyframes(
    ~layer,
    [Css.frame(~at="0%, 100%", {opacity: 1.}), Css.frame(~at="50%", {opacity: 0.5})],
  )
  let skeleton = Css.class(
    ~layer,
    {
      display: Block,
      backgroundColor: Var(Tokens.surfaceMuted),
      borderRadius: Var(Tokens.radiusSm),
      animationName: pulse,
      animationDuration: "1.6s",
      animationTimingFunction: "ease-in-out",
      animationIterationCount: "infinite",
      media: [Css.media(~query="(prefers-reduced-motion: reduce)", {animation: "none"})],
    },
  )
  let text = Css.class(
    ~layer,
    {height: Em(1.), selectors: [("&:last-child:not(:first-child)", Css.style({width: Pct(60.)}))]},
  )
  let circle = Css.class(~layer, {borderRadius: Var(Tokens.radiusFull)})
  let lines = Css.class(~layer, {display: Flex, flexDirection: Column, gap: Em(0.5)})
  /** A shape's size, set per skeleton. */
  let width = Css.var("100%")
  let height = Css.var("1em")
  let sized = Css.class(~layer, {width: Var(width), height: Var(height)})
}

@weft.component
let make = (
  ~shape: [#text | #rect | #circle]=#text,
  ~lines=1,
  ~width: option<string>=?,
  ~height: option<string>=?,
  ~className=?,
  ~dataId=?,
) => {
  let sizes = Css.vars(
    Array.concat(
      width->Option.mapOr([], width => [(Styles.width, width)]),
      height->Option.mapOr([], height => [(Styles.height, height)]),
    ),
  )
  switch shape {
  | #text =>
    <span className={Host.classes([Styles.lines], className)} style=sizes ariaHidden="true" ?dataId>
      {Array.fromInitializer(~length=Math.Int.max(1, lines), index =>
        <span key={Int.toString(index)} className={Css.cx([Styles.skeleton, Styles.text])} />
      )->WeftDom.Jsx.array}
    </span>
  | #rect | #circle =>
    <span
      className={Host.classes(
        shape == #circle
          ? [Styles.skeleton, Styles.sized, Styles.circle]
          : [Styles.skeleton, Styles.sized],
        className,
      )}
      style=sizes
      ariaHidden="true"
      ?dataId
    />
  }
}
