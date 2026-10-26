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

module Ui = WeftUi

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
    ? <Ui.EmptyState.Root bordered=true dataId="cart-empty">
        <Ui.EmptyState.Title> {WeftDom.Jsx.string("Your cart is empty.")} </Ui.EmptyState.Title>
        <Ui.EmptyState.Action>
          <Link
            dataId="keep-shopping" className={Ui.Button.className(~variant=#primary, ())} href="/"
          >
            {WeftDom.Jsx.string("Keep shopping")}
          </Link>
        </Ui.EmptyState.Action>
      </Ui.EmptyState.Root>
    : <Ui.Table.Root scrollLabel="Your cart" dataId="cart-lines">
        <Ui.Table.Caption hidden=true>
          {WeftDom.Jsx.string("What's in your cart")}
        </Ui.Table.Caption>
        <Ui.Table.Head>
          <Ui.Table.Row>
            <Ui.Table.HeaderCell> {WeftDom.Jsx.string("Item")} </Ui.Table.HeaderCell>
            <Ui.Table.HeaderCell> {WeftDom.Jsx.string("Variant")} </Ui.Table.HeaderCell>
            <Ui.Table.HeaderCell align=#center>
              {WeftDom.Jsx.string("Quantity")}
            </Ui.Table.HeaderCell>
            <Ui.Table.HeaderCell numeric=true> {WeftDom.Jsx.string("Total")} </Ui.Table.HeaderCell>
            <Ui.Table.HeaderCell>
              <Ui.VisuallyHidden> {WeftDom.Jsx.string("Remove")} </Ui.VisuallyHidden>
            </Ui.Table.HeaderCell>
          </Ui.Table.Row>
        </Ui.Table.Head>
        <Ui.Table.Body>
          {lines
          ->Array.map(line =>
            <Ui.Table.Row key=line.sku dataId={`line-${line.sku}`}>
              <Ui.Table.HeaderCell scope=#row>
                <Link href={`/p/${line.slug}`}> {WeftDom.Jsx.string(line.name)} </Link>
              </Ui.Table.HeaderCell>
              <Ui.Table.Cell> {WeftDom.Jsx.string(line.variant)} </Ui.Table.Cell>
              <Ui.Table.Cell align=#center>
                <Ui.Stack direction=#row gap=#xs align=#center justify=#center>
                  <Ui.IconButton
                    label={`One fewer ${line.name}`}
                    size=#sm
                    variant=#secondary
                    dataId={`less-${line.sku}`}
                    onClick={_ => change(line.sku, line.quantity - 1)}
                  >
                    {WeftDom.Jsx.string("−")}
                  </Ui.IconButton>
                  <Ui.Text as_=#span numeric=true dataId={`quantity-${line.sku}`}>
                    {WeftDom.Jsx.string(Int.toString(line.quantity))}
                  </Ui.Text>
                  <Ui.IconButton
                    label={`One more ${line.name}`}
                    size=#sm
                    variant=#secondary
                    dataId={`more-${line.sku}`}
                    disabled={line.quantity >= 10}
                    onClick={_ => change(line.sku, line.quantity + 1)}
                  >
                    {WeftDom.Jsx.string("+")}
                  </Ui.IconButton>
                </Ui.Stack>
              </Ui.Table.Cell>
              <Ui.Table.Cell numeric=true dataId={`total-${line.sku}`}>
                {WeftDom.Jsx.string(Money.format(line.unitPrice * line.quantity, currency))}
              </Ui.Table.Cell>
              <Ui.Table.Cell align=#end>
                <Ui.Button
                  variant=#ghost
                  size=#sm
                  dataId={`remove-${line.sku}`}
                  ariaLabel={`Remove ${line.name}`}
                  onClick={_ => change(line.sku, 0)}
                >
                  {WeftDom.Jsx.string("Remove")}
                </Ui.Button>
              </Ui.Table.Cell>
            </Ui.Table.Row>
          )
          ->WeftDom.Jsx.array}
        </Ui.Table.Body>
      </Ui.Table.Root>
}
