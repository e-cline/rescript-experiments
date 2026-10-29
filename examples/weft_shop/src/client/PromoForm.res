/*** A promo code (the `cart.applyPromo` RPC): the cart it answers with goes to the store, and the totals follow. */

module Ui = WeftUi
module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = (~applied: option<string>) => {
  let (code, setCode) = Weft.Hooks.useState(() => "")
  let (message, setMessage) = Weft.Hooks.useState(() => None)
  let apply = WeftServer.Rpc.use(Api.applyPromo)
  <Ui.Form
    dataId="promo"
    onSubmit={() =>
      (
        async () =>
          switch await apply(code) {
          | Ok(cart) =>
            Store.setCart(cart)
            setCode(_ => "")
            setMessage(_ => Some((#success, `Applied ${cart.promo->Option.getOr("")}`)))
          | Error(error) => setMessage(_ => Some((#danger, Api.describe(error))))
          }
      )()->ignore}
  >
    <Ui.Field label="Promo code">
      <Ui.Stack direction=#row gap=#sm>
        <Ui.Input
          size=#sm
          value=code
          placeholder={applied->Option.getOr("")}
          onInput={event => setCode(_ => WeftDom.Dom.Event.targetValue(event))}
        />
        <Ui.Button size=#sm dataId="apply-promo" type_=#submit> {Jsx.string("Apply")} </Ui.Button>
      </Ui.Stack>
    </Ui.Field>
    {switch message {
    | Some((tone, text)) =>
      <Ui.Text dataId="promo-message" role="status" size=#sm tone> {Jsx.string(text)} </Ui.Text>
    | None => Jsx.null
    }}
  </Ui.Form>
}
