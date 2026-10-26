@@weft.server

module Ui = WeftUi

let text = WeftDom.Jsx.string

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Dialog"
      summary="A modal dialog: the page behind it inert, the focus in it, Escape or the backdrop closing it, the focus back on its trigger."
    >
      <Specimen.Example
        caption="DialogEntry, rendered by this server component, its content the server's"
      >
        <Ui.DialogEntry
          trigger={text("Size guide")}
          title="Sizes"
          description="Measured flat, in centimetres."
          dataId="size-guide"
        >
          <Ui.Table.Root density=#compact ariaLabel="Sizes">
            <Ui.Table.Head>
              <Ui.Table.Row>
                <Ui.Table.HeaderCell> {text("Size")} </Ui.Table.HeaderCell>
                <Ui.Table.HeaderCell numeric=true> {text("Chest")} </Ui.Table.HeaderCell>
              </Ui.Table.Row>
            </Ui.Table.Head>
            <Ui.Table.Body>
              {[("S", "88–96"), ("M", "96–104"), ("L", "104–112")]
              ->Array.map(((size, chest)) =>
                <Ui.Table.Row key=size>
                  <Ui.Table.HeaderCell scope=#row> {text(size)} </Ui.Table.HeaderCell>
                  <Ui.Table.Cell numeric=true> {text(chest)} </Ui.Table.Cell>
                </Ui.Table.Row>
              )
              ->WeftDom.Jsx.array}
            </Ui.Table.Body>
          </Ui.Table.Root>
        </Ui.DialogEntry>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="AlertDialog"
      summary="A decision that matters: a click outside doesn't close it, and the focus starts on the safe choice."
    >
      <Specimen.Example caption="Cancel first; deleting adds a toast">
        <OverlayDemos.ConfirmDelete />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Drawer" summary="A dialog pinned to a side of the window, its full height."
    >
      <Specimen.Example caption="DrawerEntry, at the end and at the start">
        <Ui.Stack direction=#row gap=#sm>
          <Ui.DrawerEntry trigger={text("Open cart")} title="Your cart" dataId="drawer-end">
            <Ui.EmptyState.Root>
              <Ui.EmptyState.Title> {text("Nothing here yet")} </Ui.EmptyState.Title>
            </Ui.EmptyState.Root>
          </Ui.DrawerEntry>
          <Ui.DrawerEntry trigger={text("Open filters")} title="Filters" side=#start>
            <Ui.Text tone=#muted> {text("The filters would go here.")} </Ui.Text>
          </Ui.DrawerEntry>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Popover"
      summary="More beside what opened it: in the top layer, placed against its trigger, flipped when there's no room."
    >
      <Specimen.Example caption="PopoverEntry, below and to the end">
        <Ui.Stack direction=#row gap=#sm>
          <Ui.PopoverEntry
            trigger={text("Delivery details")} title="Delivery" dataId="popover-open"
          >
            <Ui.Text size=#sm>
              {text("Standard: 3–5 days, free. Express: next day, $9.")}
            </Ui.Text>
          </Ui.PopoverEntry>
          <Ui.PopoverEntry trigger={text("To the end")} side=#end align=#center>
            <Ui.Text size=#sm> {text("Beside its trigger.")} </Ui.Text>
          </Ui.PopoverEntry>
        </Ui.Stack>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Menu"
      summary="Actions and links behind a button: the arrow keys, Home and End, a letter to jump, Escape and Tab to leave."
    >
      <Specimen.Example caption="Links, actions, a group, a disabled item">
        <OverlayDemos.AccountMenu />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Tooltip"
      summary="A short label on hover or focus: an icon button's name, shown; or a description of a button with text."
    >
      <Specimen.Example caption="Hover or tab to them">
        <OverlayDemos.Tooltips />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Toast"
      summary="Messages that come and go, read out as they arrive; paused while the pointer or the focus is on them."
    >
      <Specimen.Example
        caption="Each tone, and one with an action (the viewport is ToastViewport, in the page's frame)"
      >
        <OverlayDemos.Toasts />
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
