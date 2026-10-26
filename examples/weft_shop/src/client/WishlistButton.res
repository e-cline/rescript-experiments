/***
Saving a product for later (the `wishlist.toggle` RPC): a toggle (pressed while it's saved, its label
the same either way), shown saved at once, put back if the server
says no. Signed out, it opens the sign-in dialog instead. The server's answer (with a refresh, or
another page) wins over what was shown.
*/

@weft.component({kind: Entrypoint})
let make = (~productId: string, ~saved as serverSaved: bool) => {
  let {user} = ShopContext.use()
  let (saved, setSaved) = Weft.Hooks.useState(() => serverSaved)
  Weft.Hooks.useEffect1(() => {
    setSaved(_ => serverSaved)
    None
  }, [serverSaved])
  let toggle = WeftServer.Rpc.use(Api.toggleWishlist)
  <WeftUi.Toggle
    label="Save to wishlist"
    variant=#ghost
    size=#sm
    dataId={`wishlist-${productId}`}
    pressed=saved
    onPressedChange={_ => {
      switch user {
      | None => Store.openSignIn()
      | Some(_) =>
        let was = saved
        setSaved(_ => !was)

        (
          async () =>
            switch await toggle(productId) {
            | Ok(now) => setSaved(_ => now)
            | Error(error) =>
              setSaved(_ => was)
              Store.toast(Api.describe(error))
            }
        )()->ignore
      }
    }}
  >
    {WeftDom.Jsx.string(saved ? "♥" : "♡")}
  </WeftUi.Toggle>
}
