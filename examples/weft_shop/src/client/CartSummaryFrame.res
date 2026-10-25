/***
The cart's totals, rendered on the server (`children`: the discount, shipping, and what's left for
free shipping are the server's to work out), fetched again by themselves (`useRefetchable`) whenever
the cart changes: the version in `ShopContext` going up, from any entrypoint's RPC.
*/

open WeftCss

module Styles = {
  let frame = Css.class({selectors: [("&[aria-busy=\"true\"]", Css.style({opacity: 0.6}))]})
}

@weft.component({kind: Entrypoint})
let make = (~children: Weft.Element.t) => {
  let {cart} = ShopContext.use()
  let summary = WeftServer.Navigation.useRefetchable(~src="/cart/summary", children)
  let refetch = Weft.Hooks.useRef(summary.refetch)
  refetch.current = summary.refetch
  let shown = Weft.Hooks.useRef(cart.version)
  Weft.Hooks.useEffect1(() => {
    if cart.version != shown.current {
      shown.current = cart.version
      refetch.current()->Promise.catch(_ => Promise.resolve())->ignore
    }
    None
  }, [cart.version])
  <div
    dataId="summary-frame" className=Styles.frame ariaBusy={summary.isPending ? "true" : "false"}
  >
    {summary.element}
  </div>
}
