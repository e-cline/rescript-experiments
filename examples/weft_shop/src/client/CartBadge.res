/***
The cart in the header: how many items (from `ShopContext`, so an RPC's answer shows at once), and a
drawer listing them, rendered into `<body>` (a portal) while it's open.
*/

open Types

open WeftCss

module Styles = {
  let drawer = Css.class({
    position: Fixed,
    top: Zero,
    right: Zero,
    bottom: Zero,
    width: Px(320),
    padding: Px(20),
    backgroundColor: Named("white"),
    borderLeft: Theme.hairline(),
    boxShadow: "-8px 0 24px #0001",
    overflow: Auto,
  })
}

module Drawer = {
  @weft.component
  let make = (~cart: cart, ~onClose: unit => unit) => {
    let {currency} = ShopContext.use()
    WeftDom.Portal.create(
      <aside id="cart-drawer" className=Styles.drawer role="dialog" ariaLabel="Cart">
        <h2> {WeftDom.Jsx.string("Your cart")} </h2>
        {cart.lines == []
          ? <p id="drawer-empty"> {WeftDom.Jsx.string("Nothing here yet.")} </p>
          : <ul id="drawer-lines">
              {cart.lines
              ->Array.map(line =>
                <li key=line.sku id={`drawer-${line.sku}`}>
                  {WeftDom.Jsx.string(
                    `${line.name} (${line.variant}) × ${Int.toString(
                        line.quantity,
                      )}: ${Money.format(line.unitPrice * line.quantity, currency)}`,
                  )}
                </li>
              )
              ->WeftDom.Jsx.array}
            </ul>}
        <p id="drawer-subtotal">
          {WeftDom.Jsx.string(`Subtotal: ${Money.format(cart.subtotal, currency)}`)}
        </p>
        // Closing as the link is followed: the drawer is the badge's, which stays on the next page.
        <div onClick={_ => onClose()}>
          <Link id="drawer-cart-link" href="/cart"> {WeftDom.Jsx.string("View cart")} </Link>
        </div>
        <button id="drawer-close" onClick={_ => onClose()}> {WeftDom.Jsx.string("Close")} </button>
      </aside>,
      ~container=WeftDom.Dom.document->WeftDom.Dom.body,
    )
  }
}

@weft.component({kind: Entrypoint})
let make = () => {
  let {cart} = ShopContext.use()
  let (isOpen, setOpen) = Weft.Hooks.useState(() => false)
  <div id="cart-badge">
    <button
      id="cart-button"
      ariaExpanded={isOpen ? "true" : "false"}
      onClick={_ => setOpen(open_ => !open_)}
    >
      {WeftDom.Jsx.string(`Cart (${Int.toString(cart.count)})`)}
    </button>
    {isOpen ? <Drawer cart onClose={() => setOpen(_ => false)} /> : WeftDom.Jsx.null}
  </div>
}
