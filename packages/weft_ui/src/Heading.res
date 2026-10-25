/***
A heading: `level` is its element (`<h1>` ... `<h6>`), and so its place in the page's outline;
`size` is how big it looks, by default the level's own.

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let heading = Css.class(
    ~layer,
    {margin: Zero, lineHeight: 1.25, fontWeight: 600, textWrap: "balance", color: Var(Tokens.fg)},
  )
  let xs = Css.class(~layer, {fontSize: Var(Tokens.textSm)})
  let sm = Css.class(~layer, {fontSize: Var(Tokens.textMd)})
  let md = Css.class(~layer, {fontSize: Var(Tokens.textLg)})
  let lg = Css.class(~layer, {fontSize: Var(Tokens.textXl)})
  let xl = Css.class(~layer, {fontSize: Var(Tokens.textXxl)})
  let xxl = Css.class(~layer, {fontSize: Var(Tokens.textXxxl), letterSpacing: Em(-0.01)})
}

type size = [#xs | #sm | #md | #lg | #xl | #xxl]

let sizeOf = (level: Variants.level): size =>
  switch level {
  | #h1 => #xxl
  | #h2 => #xl
  | #h3 => #lg
  | #h4 => #md
  | #h5 => #sm
  | #h6 => #xs
  }

/** A heading's classes, for an element of your own. */
let className = (~size: size=#lg, ()) =>
  Css.cx([
    Styles.heading,
    switch size {
    | #xs => Styles.xs
    | #sm => Styles.sm
    | #md => Styles.md
    | #lg => Styles.lg
    | #xl => Styles.xl
    | #xxl => Styles.xxl
    },
  ])

@weft.component
let make = (
  ~level: Variants.level=#h2,
  ~size: option<size>=?,
  ~id=?,
  ~className as extra=?,
  ~style=?,
  ~dataId=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=?,
) =>
  Host.element(
    Variants.levelTag(level),
    {
      ...attrs,
      ?id,
      className: Host.classes([className(~size=size->Option.getOr(sizeOf(level)), ())], extra),
      ?style,
      ?dataId,
      ?children,
    },
  )
