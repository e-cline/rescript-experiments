/*** A promo code (the `cart.applyPromo` RPC): the cart it answers with goes to the store, and the totals follow. */

@weft.component({kind: Entrypoint})
let make = (~applied: option<string>) => {
  let (code, setCode) = Weft.Hooks.useState(() => "")
  let (message, setMessage) = Weft.Hooks.useState(() => None)
  let apply = WeftServer.Rpc.use(Api.applyPromo)
  let inputId = Weft.Hooks.useId()
  <form
    id="promo"
    onSubmit={event => {
      WeftDom.Dom.Event.preventDefault(event)

      (
        async () =>
          switch await apply(code) {
          | Ok(cart) =>
            Store.setCart(cart)
            setCode(_ => "")
            setMessage(_ => Some(`Applied ${cart.promo->Option.getOr("")}`))
          | Error(error) => setMessage(_ => Some(Api.describe(error)))
          }
      )()->ignore
    }}
  >
    <label htmlFor=inputId> {WeftDom.Jsx.string("Promo code")} </label>
    <input
      id=inputId
      value=code
      placeholder={applied->Option.getOr("")}
      onInput={event => setCode(_ => WeftDom.Dom.Event.targetValue(event))}
    />
    <button id="apply-promo" type_="submit"> {WeftDom.Jsx.string("Apply")} </button>
    {switch message {
    | Some(text) => <p id="promo-message" role="status"> {WeftDom.Jsx.string(text)} </p>
    | None => WeftDom.Jsx.null
    }}
  </form>
}
