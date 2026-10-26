/***
Adds the picked variant to the cart (the `cart.add` RPC): the cart it answers with goes to the store,
so the header's count changes at once, with a toast. The quantity is this button's own state, kept
when the offer around it is fetched again for another variant (and clamped to what's in stock).
*/

@weft.component({kind: Entrypoint})
let make = (~sku: string, ~name: string, ~stock: int) => {
  let (quantity, setQuantity) = Weft.Hooks.useState(() => 1)
  let (busy, setBusy) = Weft.Hooks.useState(() => false)
  let (error, setError) = Weft.Hooks.useState(() => None)
  let add = WeftServer.Rpc.use(Api.addToCart)
  let most = Math.Int.min(stock, 10)
  let quantity = Math.Int.max(1, Math.Int.min(quantity, most))
  <WeftUi.Stack gap=#sm dataId="add-to-cart" align=#start>
    <WeftUi.Stack direction=#row gap=#sm align=#end>
      <WeftUi.Field label="Quantity">
        <WeftUi.Select
          size=#md
          disabled={stock == 0}
          value={Int.toString(quantity)}
          onChange={event => {
            let value = WeftDom.Dom.Event.targetValue(event)
            setQuantity(_ => Int.fromString(value)->Option.getOr(1))
          }}
        >
          {Array.fromInitializer(~length=Math.Int.max(1, most), index => index + 1)
          ->Array.map(count =>
            <WeftUi.Select.Option key={Int.toString(count)} value={Int.toString(count)}>
              {WeftDom.Jsx.string(Int.toString(count))}
            </WeftUi.Select.Option>
          )
          ->WeftDom.Jsx.array}
        </WeftUi.Select>
      </WeftUi.Field>
      <WeftUi.Button
        dataId="add"
        variant=#primary
        disabled={stock == 0}
        busy
        onClick={_ => {
          setBusy(_ => true)

          (
            async () => {
              switch await add({sku, quantity}) {
              | Ok(cart) =>
                setError(_ => None)
                Store.setCart(cart)
                Store.toast(`Added ${Int.toString(quantity)} × ${name} to your cart`)
              | Error(error) => setError(_ => Some(Api.describe(error)))
              }
              setBusy(_ => false)
            }
          )()->ignore
        }}
      >
        {WeftDom.Jsx.string(stock == 0 ? "Sold out" : busy ? "Adding…" : "Add to cart")}
      </WeftUi.Button>
    </WeftUi.Stack>
    {switch error {
    | Some(message) =>
      <WeftUi.Alert.Root tone=#danger dataId="add-error">
        <WeftUi.Alert.Description> {WeftDom.Jsx.string(message)} </WeftUi.Alert.Description>
      </WeftUi.Alert.Root>
    | None => WeftDom.Jsx.null
    }}
  </WeftUi.Stack>
}
