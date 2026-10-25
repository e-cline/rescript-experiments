/***
A price, in the currency the shopper picked (from `ShopContext`): changing it re-renders every price
on the page, with nothing fetched. A sale shows the price it was, struck through. A `<data>` element, its value the price in cents.
*/

open WeftCss

module Styles = {
  let was = Css.class({color: Var(Theme.muted)})
  let sale = Css.class({color: Var(Theme.sale), fontWeight: 600})
}

@weft.component({kind: Entrypoint})
let make = (~cents: Types.cents, ~compareAt: option<Types.cents>=?, ~dataId: option<string>=?) => {
  let {currency} = ShopContext.use()
  <data ?dataId value={Int.toString(cents)}>
    {switch compareAt {
    | Some(was) =>
      <>
        <s className={Styles.was}> {WeftDom.Jsx.string(Money.format(was, currency))} </s>
        {WeftDom.Jsx.string(" ")}
        <span className={Styles.sale}> {WeftDom.Jsx.string(Money.format(cents, currency))} </span>
      </>
    | None => <span> {WeftDom.Jsx.string(Money.format(cents, currency))} </span>
    }}
  </data>
}
