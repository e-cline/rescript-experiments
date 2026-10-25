/***
The cart's lines, with steppers. A change shows at once (the quantity it's going to be, kept in a
reducer while the `cart.setQuantity` RPC is out), then the cart the server answers with replaces the
lot (through the store, so the header's count follows). Lines come from `ShopContext`, the newest of
the server's cart and the client's.
*/

open Types

type pending = Map.t<string, int>

type action =
  | Change(string, int)
  | Settled(string)

let reducer = (state: pending, action) => {
  let next = Map.fromArray(state->Map.entries->Iterator.toArray)
  switch action {
  | Change(sku, quantity) => next->Map.set(sku, quantity)
  | Settled(sku) => next->Map.delete(sku)->ignore
  }
  next
}

open WeftCss

module Styles = {
  let lines = Css.class({padding: Zero, listStyle: None})
  let line = Css.class({
    display: Grid,
    gridTemplateColumns: "1fr auto auto auto auto",
    gap: Px(12),
    alignItems: Center,
    padding: Pair(Px(10), Zero),
    borderBottom: Theme.hairline(),
  })
  let stepper = Css.class({display: InlineFlex, gap: Px(6), alignItems: Center})
}

@weft.component({kind: Entrypoint})
let make = () => {
  let {cart, currency} = ShopContext.use()
  let (pending, dispatch) = Weft.Hooks.useReducer(reducer, Map.make())
  let setQuantity = WeftServer.Rpc.use(Api.setQuantity)
  let change = (sku, quantity) => {
    dispatch(Change(sku, quantity))

    (
      async () => {
        switch await setQuantity({sku, quantity}) {
        | Ok(cart) => Store.setCart(cart)
        | Error(error) => Store.toast(Api.describe(error))
        }
        dispatch(Settled(sku))
      }
    )()->ignore
  }
  let lines =
    cart.lines
    ->Array.map(line => {
      ...line,
      quantity: pending->Map.get(line.sku)->Option.getOr(line.quantity),
    })
    ->Array.filter(line => line.quantity > 0)
  lines == []
    ? <div dataId="cart-empty">
        <p> {WeftDom.Jsx.string("Your cart is empty.")} </p>
        <Link dataId="keep-shopping" href="/"> {WeftDom.Jsx.string("Keep shopping")} </Link>
      </div>
    : <ul dataId="cart-lines" className=Styles.lines>
        {lines
        ->Array.map(line =>
          <li key=line.sku dataId={`line-${line.sku}`} className={Styles.line}>
            <Link href={`/p/${line.slug}`}> {WeftDom.Jsx.string(line.name)} </Link>
            <span> {WeftDom.Jsx.string(line.variant)} </span>
            <span className={Styles.stepper}>
              <button
                dataId={`less-${line.sku}`}
                ariaLabel="One fewer"
                onClick={_ => change(line.sku, line.quantity - 1)}
              >
                {WeftDom.Jsx.string("−")}
              </button>
              <span dataId={`quantity-${line.sku}`}>
                {WeftDom.Jsx.string(Int.toString(line.quantity))}
              </span>
              <button
                dataId={`more-${line.sku}`}
                ariaLabel="One more"
                disabled={line.quantity >= 10}
                onClick={_ => change(line.sku, line.quantity + 1)}
              >
                {WeftDom.Jsx.string("+")}
              </button>
            </span>
            <span dataId={`total-${line.sku}`}>
              {WeftDom.Jsx.string(Money.format(line.unitPrice * line.quantity, currency))}
            </span>
            <button dataId={`remove-${line.sku}`} onClick={_ => change(line.sku, 0)}>
              {WeftDom.Jsx.string("Remove")}
            </button>
          </li>
        )
        ->WeftDom.Jsx.array}
      </ul>
}
