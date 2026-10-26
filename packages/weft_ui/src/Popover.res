/***
A popup with more in it (a short form, details, choices) beside what opened it: a non-modal
dialog, in the top layer (the Popover API), placed against its trigger (CSS anchor positioning),
which flips it to the other side when there's no room. Escape or a click outside closes it.

```rescript
<Popover.Root side=#bottom align=#start>
  <Popover.Trigger> {text("Share")} </Popover.Trigger>
  <Popover.Popup>
    <Popover.Title> {text("Share this note")} </Popover.Title>
    ...
    <Popover.Close> {text("Done")} </Popover.Close>
  </Popover.Popup>
</Popover.Root>
```

The trigger opens it by the platform's own `popovertarget`, so it works before the page hydrates.
As it opens, the focus goes into it; as it closes, back to the trigger.

Interactive: it keeps state, so it renders inside an entrypoint (`PopoverEntry` is one ready-made).
*/
open WeftCss

module Dom = WeftDom.Dom

module Styles = {
  let layer = Tokens.layer
  // Its layout only while it's open: a closed popover is the browser's `display: none`, which a
  // `display` of its own would override.
  let panel = Css.class(
    ~layer,
    {
      selectors: [("&:popover-open", Css.style({display: Flex}))],
      flexDirection: Column,
      gap: Var(Tokens.spaceSm),
      minInlineSize: Px(200),
      maxInlineSize: Raw("min(360px, 100vw - 16px)"),
      padding: Var(Tokens.spaceLg),
      fontSize: Var(Tokens.textSm),
      color: Var(Tokens.fg),
      backgroundColor: Var(Tokens.surface),
      border: `1px solid ${Tokens.value(Tokens.border)}`,
      borderRadius: Var(Tokens.radiusMd),
      boxShadow: Tokens.value(Tokens.shadowMd),
    },
  )
  let title = Css.class(~layer, {margin: Zero, fontSize: Var(Tokens.textMd), fontWeight: 600})
}

type state = {
  open_: bool,
  setOpen: bool => unit,
  popupId: string,
  titleId: string,
  hasTitle: bool,
  setHasTitle: bool => unit,
  anchor: string,
  side: Anchored.side,
  align: Anchored.align,
  trigger: Overlay.ref,
}

let context = Weft.Context.make({
  open_: false,
  setOpen: _ => (),
  popupId: "",
  titleId: "",
  hasTitle: false,
  setHasTitle: _ => (),
  anchor: "",
  side: #bottom,
  align: #start,
  trigger: {current: Nullable.null},
})

module Provider = {
  let make = Weft.Context.provider(context)
}

let use = () => Weft.Hooks.useContext(context)

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
    let (hasTitle, setHasTitle) = Weft.Hooks.useState(() => false)
    let trigger = Weft.Hooks.useRef(Nullable.null)
    <Provider
      value={{
        open_: current,
        setOpen: next => next != current ? setOpen(next) : (),
        popupId: `${id}-popup`,
        titleId: `${id}-title`,
        hasTitle,
        setHasTitle: has => setHasTitle(_ => has),
        anchor: Overlay.anchorName(id),
        side,
        align,
        trigger,
      }}
    >
      {children->Option.getOr(WeftDom.Jsx.null)}
    </Provider>
  }
}

module Trigger = {
  /** The button that opens and closes it. With `label`, an icon button that `label` names. */
  @weft.component
  let make = (
    ~variant: Button.variant=#secondary,
    ~size: Variants.size=#md,
    ~label: option<string>=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=WeftDom.Jsx.null,
  ) => {
    let state = use()
    Dialog.trigger(
      ~state={
        open_: state.open_,
        setOpen: state.setOpen,
        popupId: state.popupId,
        titleId: state.titleId,
        descriptionId: "",
        hasDescription: false,
        setHasDescription: _ => (),
        trigger: state.trigger,
      },
      ~haspopup="dialog",
      ~variant,
      ~size,
      ~label,
      ~className,
      ~dataId,
      ~onClick=None,
      ~attrs={
        popoverTarget: state.popupId,
        style: Anchored.triggerStyle(~anchor=state.anchor, style),
      },
      ~children,
    )
  }
}

/**
The popup's element, for `Popover` and `Menu`: an `auto` popover against the trigger, whose
toggling (by anything: its trigger, Escape, a click outside) sets the state, focusing `onOpen`'s
choice as it opens and the trigger as it closes.
*/
let popup = (
  ~open_: bool,
  ~setOpen: bool => unit,
  ~popupId: string,
  ~anchor: string,
  ~side: Anchored.side,
  ~align: Anchored.align,
  ~trigger: Overlay.ref,
  ~ref: Overlay.ref,
  ~shown: Weft.Ref.t<bool>,
  ~onOpen: Dom.element => unit,
  ~role: string,
  ~ariaLabelledby: option<string>,
  ~ariaLabel: option<string>,
  ~onKeyDown: option<Dom.event => unit>,
  ~className: string,
  ~style: option<dict<string>>,
  ~dataId: option<string>,
  ~children: Weft.Element.t,
) => {
  Anchored.usePopover(ref, ~shown, open_)
  <div
    ref
    id=popupId
    popover="auto"
    role
    tabIndex={-1}
    className={Css.cx([Anchored.Styles.anchored, className])}
    style={Anchored.popupStyle(~anchor, ~side, ~align, style)}
    ?dataId
    ?ariaLabelledby
    ?ariaLabel
    ?onKeyDown
    onToggle={event => {
      let opened = Dom.Event.newState(event) == "open"
      shown.current = opened
      let popup = Dom.Event.currentTarget(event)
      if opened {
        onOpen(popup)
      } else if Overlay.focusIsIn(popup) {
        Overlay.focusRef(trigger)
      }
      setOpen(opened)
    }}
  >
    children
  </div>
}

module Popup = {
  @weft.component
  let make = (~ariaLabel=?, ~className=?, ~style=?, ~dataId=?, ~children=WeftDom.Jsx.null) => {
    let state = use()
    let ref = Weft.Hooks.useRef(Nullable.null)
    let shown = Weft.Hooks.useRef(false)
    popup(
      ~open_=state.open_,
      ~setOpen=state.setOpen,
      ~popupId=state.popupId,
      ~anchor=state.anchor,
      ~side=state.side,
      ~align=state.align,
      ~trigger=state.trigger,
      ~ref,
      ~shown,
      ~onOpen=Overlay.focusFirst,
      ~role="dialog",
      ~ariaLabelledby=state.hasTitle && ariaLabel->Option.isNone ? Some(state.titleId) : None,
      ~ariaLabel,
      ~onKeyDown=None,
      ~className=Host.classes([Styles.panel], className),
      ~style,
      ~dataId,
      ~children,
    )
  }
}

module Title = {
  @weft.component
  let make = (~level: Variants.level=#h2, ~className=?, ~children=?) => {
    let state = use()
    Weft.Hooks.useLayoutEffect0(() => {
      state.setHasTitle(true)
      Some(() => state.setHasTitle(false))
    })
    Host.element(
      Variants.levelTag(level),
      {id: state.titleId, className: Host.classes([Styles.title], className), ?children},
    )
  }
}

module Close = {
  /** A button that closes the popover (after `onClick`, if it has one). */
  @weft.component
  let make = (
    ~variant: Button.variant=#secondary,
    ~size: Variants.size=#sm,
    ~onClick: option<Dom.event => unit>=?,
    ~className=?,
    ~dataId=?,
    ~children=WeftDom.Jsx.null,
  ) => {
    let state = use()
    <Button
      variant
      size
      ?className
      ?dataId
      onClick={event => {
        onClick->Option.forEach(onClick => onClick(event))
        state.setOpen(false)
      }}
    >
      children
    </Button>
  }
}
