/***
A dialog a server component can render as it is: a trigger (its content, `trigger`), and a dialog
with a `title`, an optional `description`, the server-rendered `children`, and a close button. Its
state is its own. For anything more (controlled, an alert, actions of its own), use `Dialog` in an
entrypoint of the app's.

```rescript
<DialogEntry trigger={text("Size guide")} title="Sizes"> <SizeTable /> </DialogEntry>
```
*/

module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = (
  ~trigger: Weft.Element.t,
  ~triggerVariant: Button.variant=#secondary,
  ~title: string,
  ~description: option<string>=?,
  ~closeLabel="Close",
  ~size: [#sm | #md | #lg]=#md,
  ~dataId: option<string>=?,
  ~children: Weft.Element.t,
) =>
  <Dialog.Root>
    <Dialog.Trigger variant=triggerVariant ?dataId> trigger </Dialog.Trigger>
    <Dialog.Popup size>
      <Dialog.Title> {Jsx.string(title)} </Dialog.Title>
      {switch description {
      | Some(description) => <Dialog.Description> {Jsx.string(description)} </Dialog.Description>
      | None => Jsx.null
      }}
      children
      <Dialog.Footer>
        <Dialog.Close> {Jsx.string(closeLabel)} </Dialog.Close>
      </Dialog.Footer>
    </Dialog.Popup>
  </Dialog.Root>
