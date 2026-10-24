/***
A price, in the currency the shopper picked (from `ShopContext`): changing it re-renders every price
on the page, with nothing fetched. A sale shows the price it was, struck through.
*/

@weft.component({kind: Entrypoint})
let make = (~cents: Types.cents, ~compareAt: option<Types.cents>=?, ~id: option<string>=?) => {
  let {currency} = ShopContext.use()
  <span ?id className="price">
    {switch compareAt {
    | Some(was) =>
      <>
        <s className="was"> {WeftDom.Jsx.string(Money.format(was, currency))} </s>
        {WeftDom.Jsx.string(" ")}
        <span className="now sale"> {WeftDom.Jsx.string(Money.format(cents, currency))} </span>
      </>
    | None => <span className="now"> {WeftDom.Jsx.string(Money.format(cents, currency))} </span>
    }}
  </span>
}
