/***
A drawer a server component can render as it is: as `DialogEntry`, with the dialog pinned to a
`side` of the window.
*/

@weft.component({kind: Entrypoint})
let make = (
  ~trigger: Weft.Element.t,
  ~triggerVariant: Button.variant=#secondary,
  ~title: string,
  ~description: option<string>=?,
  ~closeLabel="Close",
  ~side: [#start | #end]=#end,
  ~dataId: option<string>=?,
  ~children: Weft.Element.t,
) =>
  <Drawer.Root>
    <Drawer.Trigger variant=triggerVariant ?dataId> trigger </Drawer.Trigger>
    <Drawer.Popup side>
      <Drawer.Title> {WeftDom.Jsx.string(title)} </Drawer.Title>
      {switch description {
      | Some(description) =>
        <Drawer.Description> {WeftDom.Jsx.string(description)} </Drawer.Description>
      | None => WeftDom.Jsx.null
      }}
      children
      <Drawer.Footer>
        <Drawer.Close> {WeftDom.Jsx.string(closeLabel)} </Drawer.Close>
      </Drawer.Footer>
    </Drawer.Popup>
  </Drawer.Root>
