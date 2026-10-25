@@weft.server

/***
A card's sale badge: how much a product on sale is off. Its styles are its own file's (a sheet of
their own), so a page sends them only if it shows something on sale.
*/

open Types
open WeftCss

module Styles = {
  let badge = Css.class({
    display: InlineBlock,
    padding: Pair(Px(2), Px(8)),
    borderRadius: Px(999),
    backgroundColor: Var(Theme.sale),
    color: Named("white"),
    fontSize: Px(12),
    fontWeight: 600,
  })
}

/** The badge for `summary`, if it's on sale. */
@weft.component({kind: Server})
let make = (~summary: summary) =>
  switch summary.compareAt {
  | Some(was) if was > summary.price =>
    let off = Math.round(Int.toFloat(was - summary.price) /. Int.toFloat(was) *. 100.0)
    <span className={Styles.badge} dataId={`sale-${summary.id}`}>
      {WeftDom.Jsx.string(`${Float.toString(off)}% off`)}
    </span>
  | _ => WeftDom.Jsx.null
  }
