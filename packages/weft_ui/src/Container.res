/***
The page's column: centred, at most `size` wide (`Tokens.containerSm` ... `containerXl`), with a
gutter either side.

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let container = Css.class(
    ~layer,
    {
      inlineSize: Pct(100.),
      marginInline: Auto,
      paddingInline: Var(Tokens.spaceLg),
    },
  )
  let sm = Css.class(~layer, {maxInlineSize: Var(Tokens.containerSm)})
  let md = Css.class(~layer, {maxInlineSize: Var(Tokens.containerMd)})
  let lg = Css.class(~layer, {maxInlineSize: Var(Tokens.containerLg)})
  let xl = Css.class(~layer, {maxInlineSize: Var(Tokens.containerXl)})
}

@weft.component
let make = (
  ~as_: [#div | #main | #section | #header | #footer]=#div,
  ~size: [#sm | #md | #lg | #xl | #full]=#lg,
  ~id=?,
  ~className=?,
  ~style=?,
  ~dataId=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=?,
) =>
  Host.element(
    ~attrs,
    (as_ :> string),
    {
      ?id,
      className: Host.classes(
        switch size {
        | #sm => [Styles.container, Styles.sm]
        | #md => [Styles.container, Styles.md]
        | #lg => [Styles.container, Styles.lg]
        | #xl => [Styles.container, Styles.xl]
        | #full => [Styles.container]
        },
        className,
      ),
      ?style,
      ?dataId,
      ?children,
    },
  )
