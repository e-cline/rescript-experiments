/*** The overlays page's interactive examples: entrypoints, since overlays keep state. */

module Ui = WeftUi
module Jsx = WeftDom.Jsx

let text = Jsx.string

module ConfirmDelete = {
  /** An alert dialog: a decision, Cancel first, and a toast once it's done. */
  @weft.component({kind: Entrypoint})
  let make = () => {
    let (deleted, setDeleted) = Weft.Hooks.useState(() => false)
    <Ui.Stack direction=#row gap=#md align=#center>
      <Ui.AlertDialog.Root>
        <Ui.AlertDialog.Trigger variant=#danger dataId="delete-open">
          {text("Delete note")}
        </Ui.AlertDialog.Trigger>
        <Ui.AlertDialog.Popup dataId="delete-dialog">
          <Ui.AlertDialog.Title> {text("Delete this note?")} </Ui.AlertDialog.Title>
          <Ui.AlertDialog.Description>
            {text("It goes for good: there's no undo.")}
          </Ui.AlertDialog.Description>
          <Ui.AlertDialog.Footer>
            <Ui.AlertDialog.Cancel dataId="delete-cancel">
              {text("Keep it")}
            </Ui.AlertDialog.Cancel>
            <Ui.AlertDialog.Action
              variant=#danger
              dataId="delete-confirm"
              onClick={_ => {
                setDeleted(_ => true)
                Ui.Toast.add(~title="Note deleted", ~tone=#danger, ())->ignore
              }}
            >
              {text("Delete")}
            </Ui.AlertDialog.Action>
          </Ui.AlertDialog.Footer>
        </Ui.AlertDialog.Popup>
      </Ui.AlertDialog.Root>
      <Ui.Text as_=#span tone=#muted size=#sm>
        {text(deleted ? "Deleted (not really)." : "")}
      </Ui.Text>
    </Ui.Stack>
  }
}

module AccountMenu = {
  /** A menu of links and actions, with a group and a disabled item. */
  @weft.component({kind: Entrypoint})
  let make = () => {
    let (last, setLast) = Weft.Hooks.useState(() => "Nothing yet")
    let choose = name => () => setLast(_ => name)
    <Ui.Stack direction=#row gap=#md align=#center>
      <Ui.Menu.Root>
        <Ui.Menu.Trigger dataId="menu-open"> {text("Ada Lovelace ▾")} </Ui.Menu.Trigger>
        <Ui.Menu.Popup dataId="menu">
          <Ui.Menu.LinkItem href="#menu" dataId="menu-account">
            {text("Your account")}
          </Ui.Menu.LinkItem>
          <Ui.Menu.Item onSelect={choose("Orders")}> {text("Orders")} </Ui.Menu.Item>
          <Ui.Menu.Item disabled=true onSelect={choose("Billing")}>
            {text("Billing (disabled)")}
          </Ui.Menu.Item>
          <Ui.Menu.Separator />
          <Ui.Menu.Group label="Theme">
            <Ui.Menu.Item onSelect={choose("Light")}> {text("Light")} </Ui.Menu.Item>
            <Ui.Menu.Item onSelect={choose("Dark")}> {text("Dark")} </Ui.Menu.Item>
          </Ui.Menu.Group>
          <Ui.Menu.Separator />
          <Ui.Menu.Item tone=#danger onSelect={choose("Sign out")} dataId="menu-sign-out">
            {text("Sign out")}
          </Ui.Menu.Item>
        </Ui.Menu.Popup>
      </Ui.Menu.Root>
      <Ui.Text as_=#span tone=#muted size=#sm dataId="menu-last">
        {text(`Chose: ${last}`)}
      </Ui.Text>
    </Ui.Stack>
  }
}

module Tooltips = {
  /** Tooltips: naming icon buttons, and describing a text one. */
  @weft.component({kind: Entrypoint})
  let make = () =>
    <Ui.Stack direction=#row gap=#sm align=#center>
      <Ui.Tooltip.Root content="Bold">
        <Ui.Tooltip.Trigger label="Bold" variant=#ghost> {text("B")} </Ui.Tooltip.Trigger>
      </Ui.Tooltip.Root>
      <Ui.Tooltip.Root content="Italic">
        <Ui.Tooltip.Trigger label="Italic" variant=#ghost> {text("I")} </Ui.Tooltip.Trigger>
      </Ui.Tooltip.Root>
      <Ui.Tooltip.Root content="Saves a copy you can come back to" side=#bottom>
        <Ui.Tooltip.Trigger dataId="tooltip-trigger"> {text("Save draft")} </Ui.Tooltip.Trigger>
      </Ui.Tooltip.Root>
    </Ui.Stack>
}

module Toasts = {
  /** Buttons that add toasts, in each tone, one with an action. */
  @weft.component({kind: Entrypoint})
  let make = () =>
    <Ui.Stack direction=#row gap=#sm wrap=true>
      <Ui.Button
        dataId="toast-neutral" onClick={_ => Ui.Toast.add(~title="Link copied", ())->ignore}
      >
        {text("Neutral")}
      </Ui.Button>
      <Ui.Button
        onClick={_ =>
          Ui.Toast.add(
            ~title="Saved",
            ~description="Your changes are in.",
            ~tone=#success,
            (),
          )->ignore}
      >
        {text("Success")}
      </Ui.Button>
      <Ui.Button
        onClick={_ =>
          Ui.Toast.add(
            ~title="Couldn't save",
            ~description="Check your connection.",
            ~tone=#danger,
            ~duration=0,
            (),
          )->ignore}
      >
        {text("Danger (stays)")}
      </Ui.Button>
      <Ui.Button
        onClick={_ =>
          Ui.Toast.add(
            ~title="Note archived",
            ~action=("Undo", () => Ui.Toast.add(~title="Restored", ())->ignore),
            (),
          )->ignore}
      >
        {text("With an action")}
      </Ui.Button>
    </Ui.Stack>
}
