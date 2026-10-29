/***
A menu of actions (and links) behind a button: the ARIA menu button pattern.

```rescript
<Menu.Root>
  <Menu.Trigger> {text("Ada")} </Menu.Trigger>
  <Menu.Popup>
    <Menu.LinkItem href="/account" onClick=followLink> {text("Your account")} </Menu.LinkItem>
    <Menu.Separator />
    <Menu.Item onSelect=signOut> {text("Sign out")} </Menu.Item>
  </Menu.Popup>
</Menu.Root>
```

- **Opening**: Enter, Space or ArrowDown on the trigger opens it on its first item, ArrowUp on its
  last; a click opens it (the platform's `popovertarget`, so it works before hydrating) on the first.
- **In it**: ArrowDown and ArrowUp move through the items (wrapping), Home and End go to the ends, a
  letter goes to the next item starting with it, and the pointer focuses what it's over.
- **Choosing**: Enter or Space (or a click) chooses an item, which closes the menu.
- **Leaving**: Escape or a click outside closes it, and the focus goes back to the trigger; Tab
  closes it and moves on.

Disabled items are skipped. It's in the top layer, placed against its trigger (CSS anchor
positioning), flipped when there's no room.

Interactive: it keeps state, so it renders inside an entrypoint.
*/
open WeftCss
module Jsx = WeftDom.Jsx

module Dom = WeftDom.Dom

module Styles = {
  let layer = Tokens.layer
  // Its layout only while it's open (see `Popover`'s panel).
  let menu = Css.class(
    ~layer,
    {
      selectors: [("&:popover-open", Css.style({display: Flex}))],
      flexDirection: Column,
      minInlineSize: Px(180),
      maxInlineSize: Raw("min(320px, 100vw - 16px)"),
      padding: Var(Tokens.spaceXs),
      fontSize: Var(Tokens.textSm),
      color: Var(Tokens.fg),
      backgroundColor: Var(Tokens.surface),
      border: `1px solid ${Tokens.value(Tokens.border)}`,
      borderRadius: Var(Tokens.radiusMd),
      boxShadow: Tokens.value(Tokens.shadowMd),
      focusVisible: Css.style({outline: "none"}),
    },
  )
  let item = Css.class(
    ~layer,
    {
      display: Flex,
      alignItems: Center,
      gap: Var(Tokens.spaceSm),
      boxSizing: BorderBox,
      inlineSize: Pct(100.),
      minHeight: Var(Tokens.controlSm),
      padding: Pair(Px(4), Var(Tokens.spaceSm)),
      border: "none",
      borderRadius: Var(Tokens.radiusSm),
      font: "inherit",
      textAlign: Start,
      textDecoration: None,
      color: Raw("inherit"),
      backgroundColor: Transparent,
      cursor: Pointer,
      focus: Css.style({outline: "none", backgroundColor: Var(Tokens.surfaceMuted)}),
      focusVisible: Css.style({
        outline: `2px solid ${Tokens.value(Tokens.focusRing)}`,
        outlineOffset: Px(-2),
      }),
      selectors: [("&[aria-disabled=\"true\"]", Css.style({opacity: 0.5, cursor: Default}))],
    },
  )
  let danger = Css.class(~layer, {color: Var(Tokens.danger)})
  let separator = Css.class(
    ~layer,
    {
      blockSize: Px(1),
      margin: Pair(Var(Tokens.spaceXs), Zero),
      backgroundColor: Var(Tokens.border),
    },
  )
  let groupLabel = Css.class(
    ~layer,
    {
      padding: Pair(Px(4), Var(Tokens.spaceSm)),
      fontSize: Var(Tokens.textXs),
      fontWeight: 600,
      color: Var(Tokens.fgMuted),
    },
  )
}

type state = {
  open_: bool,
  setOpen: bool => unit,
  popupId: string,
  triggerId: string,
  anchor: string,
  side: Anchored.side,
  align: Anchored.align,
  trigger: Overlay.ref,
  popup: Overlay.ref,
  /** Which item to focus as it opens: the last, after ArrowUp; otherwise the first. */
  focusLast: Weft.Ref.t<bool>,
}

let context = Weft.Context.make({
  open_: false,
  setOpen: _ => (),
  popupId: "",
  triggerId: "",
  anchor: "",
  side: #bottom,
  align: #start,
  trigger: {current: Nullable.null},
  popup: {current: Nullable.null},
  focusLast: {current: false},
})

module Provider = {
  let make = Weft.Context.provider(context)
}

let use = () => Weft.Hooks.useContext(context)

/** The menu's enabled items, in order. */
let items = popup =>
  popup
  ->Dom.querySelectorAll(`.${Styles.item}`)
  ->Array.filter(item => !Dom.matches(item, "[aria-disabled=\"true\"]"))

module Root = {
  @weft.component
  let make = (
    ~open_: option<bool>=?,
    ~defaultOpen=false,
    ~onOpenChange: option<bool => unit>=?,
    ~side: Anchored.side=#bottom,
    ~align: Anchored.align=#start,
    ~children=?,
  ) => {
    let (current, setOpen) = Controllable.use(
      ~value=open_,
      ~defaultValue=defaultOpen,
      ~onChange=onOpenChange,
    )
    let id = Weft.Hooks.useId()
    let trigger = Weft.Hooks.useRef(Nullable.null)
    let popup = Weft.Hooks.useRef(Nullable.null)
    let focusLast = Weft.Hooks.useRef(false)
    <Provider
      value={{
        open_: current,
        setOpen: next => next != current ? setOpen(next) : (),
        popupId: `${id}-menu`,
        triggerId: `${id}-trigger`,
        anchor: Overlay.anchorName(id),
        side,
        align,
        trigger,
        popup,
        focusLast,
      }}
    >
      {children->Option.getOr(Jsx.null)}
    </Provider>
  }
}

module Trigger = {
  /** The button that opens it. With `label`, an icon button that `label` names. */
  @weft.component
  let make = (
    ~variant: Button.variant=#secondary,
    ~size: Variants.size=#md,
    ~label: option<string>=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=Jsx.null,
  ) => {
    let state = use()
    Button.render(
      ~className=Host.classes(
        [
          switch label {
          | Some(_) => IconButton.className(~variant, ~size, ())
          | None => Button.className(~variant, ~size, ())
          },
        ],
        className,
      ),
      ~type_=#button,
      ~busy=false,
      ~disabled=false,
      ~onClick=None,
      ~id=Some(state.triggerId),
      ~style=Some(Anchored.triggerStyle(~anchor=state.anchor, style)),
      ~dataId,
      ~ariaLabel=label,
      ~ariaDescribedby=None,
      ~ariaExpanded=Some(Host.ariaBool(state.open_)),
      ~ariaControls=Some(state.popupId),
      ~ariaHaspopup=Some("menu"),
      ~ariaPressed=None,
      ~name=None,
      ~value=None,
      ~title=None,
      ~attrs={
        ref: state.trigger,
        popoverTarget: state.popupId,
        onKeyDown: event =>
          switch Dom.Event.key(event) {
          | ("ArrowDown" | "ArrowUp") as key =>
            Dom.Event.preventDefault(event)
            state.focusLast.current = key == "ArrowUp"
            state.setOpen(true)
          | _ => ()
          },
      },
      ~children=switch label {
      | Some(_) => <span ariaHidden="true"> children </span>
      | None => children
      },
    )
  }
}

/** Typeahead: the next enabled item after `current` whose text starts with `letter`. */
let itemStartingWith = (popup, ~current, letter) => {
  let all = items(popup)
  let count = Array.length(all)
  let from = all->Array.findIndex(item => item === current)
  let letter = String.toLowerCase(letter)
  Array.fromInitializer(~length=count, offset =>
    all->Array.getUnsafe(mod(from + 1 + offset, count))
  )->Array.find(item =>
    Dom.textContent(item)->String.trim->String.toLowerCase->String.startsWith(letter)
  )
}

module Popup = {
  @weft.component
  let make = (~className=?, ~style=?, ~dataId=?, ~children=Jsx.null) => {
    let state = use()
    let shown = Weft.Hooks.useRef(false)
    Popover.popup(
      ~open_=state.open_,
      ~setOpen=state.setOpen,
      ~popupId=state.popupId,
      ~anchor=state.anchor,
      ~side=state.side,
      ~align=state.align,
      ~trigger=state.trigger,
      ~ref=state.popup,
      ~shown,
      ~onOpen=popup => {
        let all = items(popup)
        let item = state.focusLast.current ? all->Array.at(-1) : all->Array.get(0)
        state.focusLast.current = false
        switch item {
        | Some(item) => Dom.focus(item)
        | None => Dom.focus(popup)
        }
      },
      ~role="menu",
      ~ariaLabelledby=Some(state.triggerId),
      ~ariaLabel=None,
      ~onKeyDown=Some(
        event => {
          let target = Dom.Event.target(event)
          let popup = Dom.Event.currentTarget(event)
          let key = Dom.Event.key(event)
          let focusItem = item => {
            Dom.Event.preventDefault(event)
            Dom.focus(item)
          }
          let all = items(popup)
          let index = all->Array.findIndex(item => item === target)
          let count = Array.length(all)
          switch key {
          | _ if count == 0 => ()
          | "ArrowDown" => focusItem(all->Array.getUnsafe(index < 0 ? 0 : mod(index + 1, count)))
          | "ArrowUp" =>
            focusItem(all->Array.getUnsafe(index < 0 ? count - 1 : mod(index - 1 + count, count)))
          | "Home" => focusItem(all->Array.getUnsafe(0))
          | "End" => focusItem(all->Array.getUnsafe(count - 1))
          | "Tab" => state.setOpen(false)
          | letter
            if String.length(letter) == 1 &&
            letter != " " &&
            !Dom.Event.ctrlKey(event) &&
            !Dom.Event.metaKey(event) &&
            !Dom.Event.altKey(event) =>
            itemStartingWith(popup, ~current=target, letter)->Option.forEach(focusItem)
          | _ => ()
          }
        },
      ),
      ~className=Host.classes([Styles.menu], className),
      ~style,
      ~dataId,
      ~children,
    )
  }
}

/** An item's shared behaviour: focused by the pointer, closing the menu once chosen. */
let itemAttrs = (state: state): WeftDom.DomProps.props => {
  tabIndex: -1,
  onPointerMove: event => {
    let item = Dom.Event.currentTarget(event)
    if !Dom.matches(item, "[aria-disabled=\"true\"]") {
      Dom.focus(item)
    }
  },
  onPointerLeave: _ => state.popup.current->Nullable.forEach(Dom.focus),
}

module Item = {
  /** An action: `onSelect` runs when it's chosen, and the menu closes. */
  @weft.component
  let make = (
    ~onSelect: option<unit => unit>=?,
    ~disabled=false,
    ~tone: [#default | #danger]=#default,
    ~className=?,
    ~dataId=?,
    ~children=?,
  ) => {
    let state = use()
    Host.withAttrs(
      itemAttrs(state),
      <button
        type_="button"
        role="menuitem"
        className={Host.classes(
          tone == #danger ? [Styles.item, Styles.danger] : [Styles.item],
          className,
        )}
        ?dataId
        ariaDisabled=?{disabled ? Some("true") : None}
        onClick={_ =>
          if !disabled {
            onSelect->Option.forEach(onSelect => onSelect())
            state.setOpen(false)
          }}
        ?children
      />,
    )
  }
}

module LinkItem = {
  /**
  A link: following it closes the menu. `onClick` gets the click first (an app's in-place
  navigation, say).
  */
  @weft.component
  let make = (
    ~href: string,
    ~onClick: option<Dom.event => unit>=?,
    ~className=?,
    ~dataId=?,
    ~children=?,
  ) => {
    let state = use()
    Host.withAttrs(
      itemAttrs(state),
      <a
        href
        role="menuitem"
        className={Host.classes([Styles.item], className)}
        ?dataId
        onClick={event => {
          onClick->Option.forEach(onClick => onClick(event))
          state.setOpen(false)
        }}
        ?children
      />,
    )
  }
}

module Separator = {
  @weft.component
  let make = () => <div role="separator" className=Styles.separator />
}

module Group = {
  /** Items under a heading, `label`. */
  @weft.component
  let make = (~label: string, ~children=?) => {
    let id = Weft.Hooks.useId()
    <div role="group" ariaLabelledby=id>
      <div id className=Styles.groupLabel ariaHidden="true"> {Jsx.string(label)} </div>
      {children->Option.getOr(Jsx.null)}
    </div>
  }
}
