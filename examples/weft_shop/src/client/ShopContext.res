/***
What every part of the page shares, from `ShopShell`: the currency prices are shown in (and how to
change it), who's signed in, and the cart, the newest of the server's and the client's own (from an
RPC's answer).

A plain client module, imported by several entrypoints: each chunk gets the same module (Vite puts
it in a chunk they share), so they find the one context.
*/

open Types

type value = {
  currency: currency,
  setCurrency: currency => unit,
  user: option<string>,
  cart: cart,
}

let context = Weft.Context.make({
  currency: USD,
  setCurrency: _ => (),
  user: None,
  cart: emptyCart,
})

module Provider = {
  let make = Weft.Context.provider(context)
}

let use = () => Weft.Hooks.useContext(context)
