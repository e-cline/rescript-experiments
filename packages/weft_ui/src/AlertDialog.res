/***
A dialog asking for a decision that matters ("Delete this note?"): an `alertdialog`, which a click
outside doesn't close (Escape still does, as no). As it opens, the focus goes to `Cancel`, the safe
choice.

```rescript
<AlertDialog.Root>
  <AlertDialog.Trigger variant=#danger> {text("Delete")} </AlertDialog.Trigger>
  <AlertDialog.Popup>
    <AlertDialog.Title> {text("Delete this note?")} </AlertDialog.Title>
    <AlertDialog.Description> {text("It can't be undone.")} </AlertDialog.Description>
    <Dialog.Footer>
      <AlertDialog.Cancel> {text("Keep it")} </AlertDialog.Cancel>
      <AlertDialog.Action variant=#danger onClick=delete> {text("Delete")} </AlertDialog.Action>
    </Dialog.Footer>
  </AlertDialog.Popup>
</AlertDialog.Root>
```

Interactive: it keeps state, so it renders inside an entrypoint.
*/

module Root = Dialog.Root
module Trigger = Dialog.Trigger
module Title = Dialog.Title
module Description = Dialog.Description
module Footer = Dialog.Footer
module Jsx = WeftDom.Jsx

module Popup = {
  @weft.component
  let make = (
    ~size: [#sm | #md | #lg]=#sm,
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
      ~size,
      ~placement=#center,
      ~role=Some("alertdialog"),
      ~dismissible=false,
      ~ariaLabel,
      ~className,
      ~style,
      ~dataId,
      ~children,
    )
  }
}

module Cancel = {
  /** Closes the dialog, deciding nothing: where the focus starts. */
  @weft.component
  let make = (~className=?, ~dataId=?, ~children=Jsx.null) =>
    <Dialog.Close autoFocus=true ?className ?dataId> children </Dialog.Close>
}

module Action = {
  /** Does what the dialog asks about (`onClick`), and closes it. */
  @weft.component
  let make = (
    ~variant: Button.variant=#primary,
    ~onClick: option<WeftDom.Dom.event => unit>=?,
    ~className=?,
    ~dataId=?,
    ~children=Jsx.null,
  ) => <Dialog.Close variant ?onClick ?className ?dataId> children </Dialog.Close>
}
