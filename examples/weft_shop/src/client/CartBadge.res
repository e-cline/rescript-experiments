/***
The cart in the header: how many items (from `ShopContext`, so an RPC's answer shows at once), and a
drawer listing them (weft_ui's `Drawer`: modal, Escape or a click outside closes it, the focus back
on the button).
*/

open Types

module Ui = WeftUi

@weft.component({kind: Entrypoint})
let make = () => {
  let {cart, currency} = ShopContext.use()
  let (isOpen, setOpen) = Weft.Hooks.useState(() => false)
  let navigation = WeftServer.Navigation.useNavigation()
  <div dataId="cart-badge">
    <Ui.Drawer.Root open_=isOpen onOpenChange={open_ => setOpen(_ => open_)}>
      <Ui.Drawer.Trigger dataId="cart-button">
        {WeftDom.Jsx.string(`Cart (${Int.toString(cart.count)})`)}
      </Ui.Drawer.Trigger>
      <Ui.Drawer.Popup dataId="cart-drawer">
        <Ui.Drawer.Title> {WeftDom.Jsx.string("Your cart")} </Ui.Drawer.Title>
        {cart.lines == []
          ? <Ui.EmptyState.Root dataId="drawer-empty">
              <Ui.EmptyState.Title> {WeftDom.Jsx.string("Nothing here yet.")} </Ui.EmptyState.Title>
            </Ui.EmptyState.Root>
          : <Ui.List.Root divided=true dataId="drawer-lines">
              {cart.lines
              ->Array.map(line =>
                <Ui.List.Item key=line.sku dataId={`drawer-${line.sku}`}>
                  {WeftDom.Jsx.string(
                    `${line.name} (${line.variant}) × ${Int.toString(
                        line.quantity,
                      )}: ${Money.format(line.unitPrice * line.quantity, currency)}`,
                  )}
                </Ui.List.Item>
              )
              ->WeftDom.Jsx.array}
            </Ui.List.Root>}
        <Ui.Text weight=#semibold dataId="drawer-subtotal">
          {WeftDom.Jsx.string(`Subtotal: ${Money.format(cart.subtotal, currency)}`)}
        </Ui.Text>
        <Ui.Drawer.Footer>
          <Ui.Drawer.Close dataId="drawer-close" variant=#ghost>
            {WeftDom.Jsx.string("Close")}
          </Ui.Drawer.Close>
          // Closing as the link is followed: the drawer is the badge's, which stays on the next page.
          <a
            dataId="drawer-cart-link"
            className={Ui.Button.className(~variant=#primary, ())}
            href="/cart"
            onClick={event => {
              setOpen(_ => false)
              navigation->WeftServer.Navigation.followLink(event, ~href="/cart")->ignore
            }}
          >
            {WeftDom.Jsx.string("View cart")}
          </a>
        </Ui.Drawer.Footer>
      </Ui.Drawer.Popup>
    </Ui.Drawer.Root>
  </div>
}
