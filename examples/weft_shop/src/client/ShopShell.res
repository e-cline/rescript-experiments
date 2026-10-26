/***
The page around every page: the shared context (`ShopContext`) for what's below, the toasts (weft_ui's), the
sign-in dialog and the offline banner. It stays in place as the shopper navigates, so the currency
they picked here, and the toasts, carry over.

The server gives it the session's currency, user and cart with every page (a navigation or a refresh
brings new ones); the cart an RPC answered with since (in `Store`) wins over them until a newer one
comes from the server.
*/

open Types

@weft.component({kind: Entrypoint})
let make = (
  ~currency as serverCurrency: currency,
  ~user: option<string>,
  ~cart as serverCart: cart,
  ~children: Weft.Element.t,
) => {
  let (currency, setCurrency) = Weft.Hooks.useState(() => serverCurrency)
  // The server's currency, when it changes (picked in another tab, say), wins.
  Weft.Hooks.useEffect1(() => {
    setCurrency(_ => serverCurrency)
    None
  }, [serverCurrency])
  // Which shell this is, so it doesn't believe a cart a page before it left in the store.
  let owner = Weft.Hooks.useRef(Math.random())
  let stored = WeftSignals.SignalHooks.useSignal(Signals.Atom.toSignal(Store.cart))
  Weft.Hooks.useEffect1(() => {
    Store.offerCart(~owner=owner.current, serverCart)
    None
  }, [serverCart.version])
  let cart = switch stored {
  | Some((found, cart)) if found == owner.current && cart.version >= serverCart.version => cart
  | _ => serverCart
  }
  let value: ShopContext.value = {
    currency,
    setCurrency: next => setCurrency(_ => next),
    user,
    cart,
  }
  <ShopContext.Provider value>
    <OnlineBanner />
    children
    <WeftUi.Toast.Viewport dataId="toasts" />
    <SignInDialog />
  </ShopContext.Provider>
}
