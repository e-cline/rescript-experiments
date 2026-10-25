/***
Terms and what they are: a summary's lines (Subtotal, $40), a product's details. In a `#grid`, each
term sits beside its details (`detailsAlign=#end` puts amounts at the end); `#stacked`, above them.

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let list = Css.class(~layer, {margin: Zero, display: Grid})
  let grid = Css.class(
    ~layer,
    {
      gridTemplateColumns: "auto minmax(0, 1fr)",
      columnGap: Var(Tokens.spaceLg),
      rowGap: Var(Tokens.spaceSm),
      alignItems: Baseline,
    },
  )
  let stacked = Css.class(
    ~layer,
    {
      gridTemplateColumns: "minmax(0, 1fr)",
      selectors: [("dd + dt", Css.style({marginBlockStart: Var(Tokens.spaceMd)}))],
    },
  )
  let detailsEnd = Css.class(
    ~layer,
    {selectors: [("dd", Css.style({textAlign: End, fontVariantNumeric: TabularNums}))]},
  )
  let term = Css.class(~layer, {color: Var(Tokens.fgMuted)})
  let details = Css.class(~layer, {margin: Zero, color: Var(Tokens.fg)})
}

module Root = {
  @weft.component
  let make = (
    ~layout: [#grid | #stacked]=#grid,
    ~detailsAlign: [#start | #end]=#start,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~attrs: WeftDom.DomProps.props={},
    ~children=?,
  ) =>
    <dl
      {...attrs}
      ?id
      className={Host.classes(
        Array.concat(
          [Styles.list, layout == #grid ? Styles.grid : Styles.stacked],
          detailsAlign == #end ? [Styles.detailsEnd] : [],
        ),
        className,
      )}
      ?style
      ?dataId
      ?children
    />
}

module Term = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <dt ?id className={Host.classes([Styles.term], className)} ?dataId ?children />
}

module Details = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <dd ?id className={Host.classes([Styles.details], className)} ?dataId ?children />
}
