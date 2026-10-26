/***
The overlays in jsdom, with `Testing.installJsdomShims` standing in for `<dialog>` and the Popover
API: their ARIA, their state, the keyboard, and where the focus goes. How they look and stack (the
top layer, inertness, anchor positioning) is for the browser tests.
*/
open Vitest
open Support

Testing.installJsdomShims()

let isOpen = element => element->attribute("open")->Option.isSome
let isShown = element => element->attribute("data-popover-open")->Option.isSome
let focused = element => activeElement() == Some(element)
let escape = () => keyDown(activeElement()->Option.getOrThrow, "Escape")->ignore

afterEach(() => Dom.setTextContent(Dom.body(Dom.document), ""))

describe("Dialog", () => {
  let dialog = (~onOpenChange=?, ~dismissible=?, ()) =>
    mount(
      <Dialog.Root ?onOpenChange>
        <Dialog.Trigger dataId="open"> {text("Sign in")} </Dialog.Trigger>
        <Dialog.Popup ?dismissible>
          <Dialog.Title> {text("Sign in")} </Dialog.Title>
          <Dialog.Description> {text("With your name")} </Dialog.Description>
          <Input ariaLabel="Name" dataId="name" />
          <Dialog.Close dataId="close"> {text("Close")} </Dialog.Close>
        </Dialog.Popup>
      </Dialog.Root>,
    )

  test("its trigger says what it opens, and opening it focuses the first field", t => {
    let container = dialog()
    let trigger = find(container, "[data-id=open]")
    let popup = find(container, "dialog")
    t->expect(attribute(trigger, "aria-haspopup"))->Expect.toEqual(Some("dialog"))
    t->expect(attribute(trigger, "aria-controls"))->Expect.toEqual(attribute(popup, "id"))
    t->expect(attribute(trigger, "aria-expanded"))->Expect.toEqual(Some("false"))
    t->expect(isOpen(popup))->Expect.toBe(false)
    click(trigger)
    t->expect(isOpen(popup))->Expect.toBe(true)
    t->expect(attribute(trigger, "aria-expanded"))->Expect.toEqual(Some("true"))
    t->expect(focused(find(container, "[data-id=name]")))->Expect.toBe(true)
  })

  test("is named by its title, and described by its description", t => {
    let container = dialog()
    let popup = find(container, "dialog")
    let labelledBy = attribute(popup, "aria-labelledby")->Option.getOr("")
    let describedBy = attribute(popup, "aria-describedby")->Option.getOr("")
    t->expect(Dom.textContent(find(container, `#${labelledBy}`)))->Expect.toBe("Sign in")
    t->expect(Dom.textContent(find(container, `#${describedBy}`)))->Expect.toBe("With your name")
  })

  test("closes by its close button, Escape or its backdrop, the focus back on the trigger", t => {
    let changes = []
    let container = dialog(~onOpenChange=open_ => changes->Array.push(open_), ())
    let trigger = find(container, "[data-id=open]")
    let popup = find(container, "dialog")
    click(trigger)
    click(find(container, "[data-id=close]"))
    t->expect(isOpen(popup))->Expect.toBe(false)
    t->expect(focused(trigger))->Expect.toBe(true)
    click(trigger)
    escape()
    t->expect(isOpen(popup))->Expect.toBe(false)
    t->expect(attribute(trigger, "aria-expanded"))->Expect.toEqual(Some("false"))
    click(trigger)
    // A click on the dialog itself, not its content, is on its backdrop.
    click(popup)
    t->expect(isOpen(popup))->Expect.toBe(false)
    t->expect(changes)->Expect.toEqual([true, false, true, false, true, false])
  })

  test("a click inside doesn't close it, nor one outside when it isn't dismissible", t => {
    let container = dialog(~dismissible=false, ())
    click(find(container, "[data-id=open]"))
    click(find(container, "[data-id=name]"))
    let popup = find(container, "dialog")
    t->expect(isOpen(popup))->Expect.toBe(true)
    click(popup)
    t->expect(isOpen(popup))->Expect.toBe(true)
  })

  test("a controlled one opens and closes with its prop", t => {
    let container = mount(
      <Dialog.Root open_=true>
        <Dialog.Popup ariaLabel="Settings"> {text("Settings")} </Dialog.Popup>
      </Dialog.Root>,
    )
    let popup = find(container, "dialog")
    t->expect(isOpen(popup))->Expect.toBe(true)
    t->expect(attribute(popup, "aria-label"))->Expect.toEqual(Some("Settings"))
    t->expect(attribute(popup, "aria-labelledby"))->Expect.toEqual(None)
  })
})

describe("AlertDialog and Drawer", () => {
  test("an alert dialog is an alertdialog, starts on Cancel, and Action acts and closes", t => {
    let deleted = ref(false)
    let container = mount(
      <AlertDialog.Root>
        <AlertDialog.Trigger dataId="open"> {text("Delete")} </AlertDialog.Trigger>
        <AlertDialog.Popup>
          <AlertDialog.Title> {text("Delete this note?")} </AlertDialog.Title>
          <AlertDialog.Footer>
            <AlertDialog.Cancel dataId="cancel"> {text("Keep it")} </AlertDialog.Cancel>
            <AlertDialog.Action dataId="delete" onClick={_ => deleted := true}>
              {text("Delete")}
            </AlertDialog.Action>
          </AlertDialog.Footer>
        </AlertDialog.Popup>
      </AlertDialog.Root>,
    )
    click(find(container, "[data-id=open]"))
    let popup = find(container, "dialog")
    t->expect(attribute(popup, "role"))->Expect.toEqual(Some("alertdialog"))
    t->expect(focused(find(container, "[data-id=cancel]")))->Expect.toBe(true)
    click(popup)
    t->expect(isOpen(popup))->Expect.toBe(true)
    click(find(container, "[data-id=delete]"))
    t->expect((deleted.contents, isOpen(popup)))->Expect.toEqual((true, false))
  })

  test("a drawer is a dialog pinned to its side", t => {
    let container = mount(
      <Drawer.Root>
        <Drawer.Trigger> {text("Cart")} </Drawer.Trigger>
        <Drawer.Popup side=#start>
          <Drawer.Title> {text("Your cart")} </Drawer.Title>
        </Drawer.Popup>
      </Drawer.Root>,
    )
    click(find(container, "button"))
    let popup = find(container, "dialog")
    t->expect(isOpen(popup))->Expect.toBe(true)
    t->expect(has(popup, Dialog.Styles.side) && has(popup, Dialog.Styles.start))->Expect.toBe(true)
  })
})

describe("Popover", () => {
  test("its trigger toggles it (popovertarget), the focus going in and back", t => {
    let container = mount(
      <Popover.Root>
        <Popover.Trigger dataId="open"> {text("Share")} </Popover.Trigger>
        <Popover.Popup>
          <Popover.Title> {text("Share this note")} </Popover.Title>
          <Input ariaLabel="Link" dataId="link" />
          <Popover.Close dataId="done"> {text("Done")} </Popover.Close>
        </Popover.Popup>
      </Popover.Root>,
    )
    let trigger = find(container, "[data-id=open]")
    let popup = find(container, "[popover]")
    t->expect(attribute(trigger, "popovertarget"))->Expect.toEqual(attribute(popup, "id"))
    t->expect(attribute(popup, "popover"))->Expect.toEqual(Some("auto"))
    t->expect(attribute(popup, "role"))->Expect.toEqual(Some("dialog"))
    click(trigger)
    t->expect(isShown(popup))->Expect.toBe(true)
    t->expect(attribute(trigger, "aria-expanded"))->Expect.toEqual(Some("true"))
    t->expect(focused(find(container, "[data-id=link]")))->Expect.toBe(true)
    let labelledBy = attribute(popup, "aria-labelledby")->Option.getOr("")
    t->expect(Dom.textContent(find(container, `#${labelledBy}`)))->Expect.toBe("Share this note")
    escape()
    t->expect(isShown(popup))->Expect.toBe(false)
    t->expect(attribute(trigger, "aria-expanded"))->Expect.toEqual(Some("false"))
    t->expect(focused(trigger))->Expect.toBe(true)
    click(trigger)
    click(find(container, "[data-id=done]"))
    t->expect(isShown(popup))->Expect.toBe(false)
  })

  test("is placed against its trigger, by an anchor name they share", t => {
    let container = mount(
      <Popover.Root side=#top align=#end>
        <Popover.Trigger> {text("Share")} </Popover.Trigger>
        <Popover.Popup> {text("Hi")} </Popover.Popup>
      </Popover.Root>,
    )
    let triggerStyle = attribute(find(container, "button"), "style")->Option.getOr("")
    let popupStyle = attribute(find(container, "[popover]"), "style")->Option.getOr("")
    t->expect(triggerStyle->String.includes("anchor-name: --"))->Expect.toBe(true)
    t->expect(popupStyle->String.includes("position-anchor: --"))->Expect.toBe(true)
    t
    ->expect(popupStyle->String.includes("position-area: block-start span-inline-start"))
    ->Expect.toBe(true)
  })
})

describe("Menu", () => {
  let chosen = []
  let menu = () => {
    chosen->Array.splice(~start=0, ~remove=Array.length(chosen), ~insert=[])
    mount(
      <Menu.Root>
        <Menu.Trigger dataId="open"> {text("Ada")} </Menu.Trigger>
        <Menu.Popup>
          <Menu.LinkItem href="/account" dataId="account"> {text("Account")} </Menu.LinkItem>
          <Menu.Item dataId="archive" disabled=true onSelect={() => chosen->Array.push("archive")}>
            {text("Archive")}
          </Menu.Item>
          <Menu.Separator />
          <Menu.Item dataId="settings" onSelect={() => chosen->Array.push("settings")}>
            {text("Settings")}
          </Menu.Item>
          <Menu.Item dataId="sign-out" onSelect={() => chosen->Array.push("sign out")}>
            {text("Sign out")}
          </Menu.Item>
        </Menu.Popup>
      </Menu.Root>,
    )
  }

  test("is a menu button: the menu labelled by its trigger, its items menuitems", t => {
    let container = menu()
    let trigger = find(container, "[data-id=open]")
    let popup = find(container, "[role=menu]")
    t->expect(attribute(trigger, "aria-haspopup"))->Expect.toEqual(Some("menu"))
    t->expect(attribute(popup, "aria-labelledby"))->Expect.toEqual(attribute(trigger, "id"))
    t->expect(findAll(popup, "[role=menuitem]")->Array.length)->Expect.toBe(4)
    t
    ->expect(findAll(popup, "[role=menuitem]")->Array.map(item => attribute(item, "tabindex")))
    ->Expect.toEqual([Some("-1"), Some("-1"), Some("-1"), Some("-1")])
  })

  test(
    "ArrowDown opens it on its first item, ArrowUp on its last; the arrows skip disabled ones",
    t => {
      let container = menu()
      let trigger = find(container, "[data-id=open]")
      focus(trigger)
      keyDown(trigger, "ArrowDown")->ignore
      t->expect(isShown(find(container, "[role=menu]")))->Expect.toBe(true)
      t->expect(focused(find(container, "[data-id=account]")))->Expect.toBe(true)
      keyDown(find(container, "[data-id=account]"), "ArrowDown")->ignore
      t->expect(focused(find(container, "[data-id=settings]")))->Expect.toBe(true)
      keyDown(find(container, "[data-id=settings]"), "End")->ignore
      t->expect(focused(find(container, "[data-id=sign-out]")))->Expect.toBe(true)
      keyDown(find(container, "[data-id=sign-out]"), "ArrowDown")->ignore
      t->expect(focused(find(container, "[data-id=account]")))->Expect.toBe(true)
      escape()
      t->expect(focused(trigger))->Expect.toBe(true)
      keyDown(trigger, "ArrowUp")->ignore
      t->expect(focused(find(container, "[data-id=sign-out]")))->Expect.toBe(true)
    },
  )

  test("a letter goes to the next item starting with it", t => {
    let container = menu()
    click(find(container, "[data-id=open]"))
    keyDown(find(container, "[data-id=account]"), "s")->ignore
    t->expect(focused(find(container, "[data-id=settings]")))->Expect.toBe(true)
    keyDown(find(container, "[data-id=settings]"), "s")->ignore
    t->expect(focused(find(container, "[data-id=sign-out]")))->Expect.toBe(true)
  })

  test("choosing an item runs it and closes the menu, the focus back on the trigger", t => {
    let container = menu()
    let trigger = find(container, "[data-id=open]")
    click(trigger)
    click(find(container, "[data-id=archive]"))
    t->expect(chosen)->Expect.toEqual([])
    t->expect(isShown(find(container, "[role=menu]")))->Expect.toBe(true)
    click(find(container, "[data-id=sign-out]"))
    t->expect(chosen)->Expect.toEqual(["sign out"])
    t->expect(isShown(find(container, "[role=menu]")))->Expect.toBe(false)
    t->expect(focused(trigger))->Expect.toBe(true)
  })
})

describe("Tooltip", () => {
  test("shows on focus, hides on Escape and blur, and describes a trigger with no label", t => {
    let container = mount(
      <Tooltip.Root content="Saves a copy">
        <Tooltip.Trigger dataId="save"> {text("Save")} </Tooltip.Trigger>
      </Tooltip.Root>,
    )
    let trigger = find(container, "[data-id=save]")
    let tooltip = find(container, "[role=tooltip]")
    t->expect(attribute(trigger, "aria-describedby"))->Expect.toEqual(attribute(tooltip, "id"))
    t->expect(attribute(tooltip, "popover"))->Expect.toEqual(Some("manual"))
    focus(trigger)
    t->expect(isShown(tooltip))->Expect.toBe(true)
    keyDown(trigger, "Escape")->ignore
    t->expect(isShown(tooltip))->Expect.toBe(false)
    focus(trigger)
    blur(trigger)
    t->expect(isShown(tooltip))->Expect.toBe(false)
  })

  test("with a label, names an icon trigger, which it then doesn't describe too", t => {
    let container = mount(
      <Tooltip.Root content="Dismiss">
        <Tooltip.Trigger label="Dismiss"> {text("×")} </Tooltip.Trigger>
      </Tooltip.Root>,
    )
    let trigger = find(container, "button")
    t->expect(attribute(trigger, "aria-label"))->Expect.toEqual(Some("Dismiss"))
    t->expect(attribute(trigger, "aria-describedby"))->Expect.toEqual(None)
  })
})

describe("Toast", () => {
  let tick = ms => Promise.make((resolve, _) => setTimeout(() => resolve(), ms)->ignore)

  testAsync(
    "shows what's added, in a polite region, an alert for danger, until dismissed",
    async t => {
      let manager = Toast.createManager()
      let container = mount(<Toast.Viewport manager />)
      t->expect(attribute(find(container, "ol"), "aria-live"))->Expect.toEqual(Some("polite"))
      WeftDom.Client.act(
        () => {
          Toast.add(~manager, ~title="Saved", ~duration=0, ())->ignore
          Toast.add(~manager, ~title="Couldn't save", ~tone=#danger, ~duration=0, ())->ignore
        },
      )
      let toasts = findAll(container, "li")
      t->expect(toasts->Array.map(Dom.textContent))->Expect.toEqual(["Saved×", "Couldn't save×"])
      t
      ->expect(toasts->Array.map(toast => attribute(toast, "role")))
      ->Expect.toEqual([None, Some("alert")])
      click(find(toasts->Array.getUnsafe(0), "[aria-label=Dismiss]"))
      t->expect(findAll(container, "li")->Array.length)->Expect.toBe(1)
      await tick(0)
    },
  )

  testAsync("goes after its duration, but not while the pointer's on the toasts", async t => {
    let manager = Toast.createManager()
    let container = mount(<Toast.Viewport manager />)
    WeftDom.Client.act(() => Toast.add(~manager, ~title="Brief", ~duration=30, ())->ignore)
    let list = find(container, "ol")
    WeftDom.Client.act(() => Dom.dispatchEvent(list, Dom.Event.make("pointerenter", {})))
    await tick(60)
    t->expect(findAll(container, "li")->Array.length)->Expect.toBe(1)
    WeftDom.Client.act(() => Dom.dispatchEvent(list, Dom.Event.make("pointerleave", {})))
    await tick(60)
    t->expect(findAll(container, "li")->Array.length)->Expect.toBe(0)
  })
})
