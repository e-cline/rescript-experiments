/***
A dialog pinned to one side of the window (`side`, the inline end by default), its full height:
a cart, filters on a phone, a menu. It's a `Dialog` in every other way: modal, Escape and a click
outside close it, and the focus goes back to its trigger.

```rescript
<Drawer.Root>
  <Drawer.Trigger> {text("Cart (2)")} </Drawer.Trigger>
  <Drawer.Popup>
    <Drawer.Title> {text("Your cart")} </Drawer.Title>
    ...
    <Drawer.Close> {text("Close")} </Drawer.Close>
  </Drawer.Popup>
</Drawer.Root>
```

Interactive: it keeps state, so it renders inside an entrypoint (`DrawerEntry` is one ready-made).
*/

module Root = Dialog.Root
module Trigger = Dialog.Trigger
module Title = Dialog.Title
module Description = Dialog.Description
module Footer = Dialog.Footer
module Close = Dialog.Close
module Jsx = WeftDom.Jsx

module Popup = {
  @weft.component
  let make = (
    ~side: [#start | #end]=#end,
    ~dismissible=true,
    ~ariaLabel=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=Jsx.null,
  ) => {
    let state = Dialog.use()
    let ref = Weft.Hooks.useRef(Nullable.null)
    Dialog.useModal(ref, state.open_)
    Dialog.popup(
      ~state,
      ~ref,
      ~size=#md,
      ~placement=(side :> Dialog.placement),
      ~role=None,
      ~dismissible,
      ~ariaLabel,
      ~className,
      ~style,
      ~dataId,
      ~children,
    )
  }
}
