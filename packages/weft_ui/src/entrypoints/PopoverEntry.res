/***
A popover a server component can render as it is: a trigger (its content, `trigger`), and the
server-rendered `children` beside it, with an optional `title`. Its state is its own.
*/

module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = (
  ~trigger: Weft.Element.t,
  ~triggerVariant: Button.variant=#secondary,
  ~title: option<string>=?,
  ~side: Anchored.side=#bottom,
  ~align: Anchored.align=#start,
  ~dataId: option<string>=?,
  ~children: Weft.Element.t,
) =>
  <Popover.Root side align>
    <Popover.Trigger variant=triggerVariant ?dataId> trigger </Popover.Trigger>
    <Popover.Popup>
      {switch title {
      | Some(title) => <Popover.Title> {Jsx.string(title)} </Popover.Title>
      | None => Jsx.null
      }}
      children
    </Popover.Popup>
  </Popover.Root>
