/***
A short label for a control, shown while it's hovered (after `delay`) or focused, and hidden on
Escape, leaving, or blur. Never the only name of anything: an icon button's `label` names it, and
the tooltip shows that label to sighted pointer users; otherwise the tooltip describes the trigger
(`aria-describedby`).

```rescript
<Tooltip.Root content="Save to wishlist">
  <Tooltip.Trigger label="Save to wishlist" variant=#ghost> {text("♡")} </Tooltip.Trigger>
</Tooltip.Root>
```

Interactive: it keeps state, so it renders inside an entrypoint.
*/
open WeftCss

module Dom = WeftDom.Dom

module Styles = {
  let layer = Tokens.layer
  let tooltip = Css.class(
    ~layer,
    {
      maxInlineSize: Px(240),
      padding: Pair(Px(4), Var(Tokens.spaceSm)),
      fontSize: Var(Tokens.textXs),
      lineHeight: 1.4,
      color: Var(Tokens.bg),
      backgroundColor: Var(Tokens.fg),
      borderRadius: Var(Tokens.radiusSm),
      pointerEvents: None,
    },
  )
}

type state = {
  open_: bool,
  show: (~now: bool) => unit,
  hide: unit => unit,
  popupId: string,
  anchor: string,
  content: string,
  side: Anchored.side,
}

let context = Weft.Context.make({
  open_: false,
  show: (~now as _) => (),
  hide: () => (),
  popupId: "",
  anchor: "",
  content: "",
  side: #top,
})

module Provider = {
  let make = Weft.Context.provider(context)
}

module Popup = {
  @weft.component
  let make = () => {
    let state = Weft.Hooks.useContext(context)
    let ref = Weft.Hooks.useRef(Nullable.null)
    let shown = Weft.Hooks.useRef(false)
    Anchored.usePopover(ref, ~shown, state.open_)
    <div
      ref
      id=state.popupId
      popover="manual"
      role="tooltip"
      className={Css.cx([Anchored.Styles.anchored, Styles.tooltip])}
      style={Anchored.popupStyle(~anchor=state.anchor, ~side=state.side, ~align=#center, None)}
    >
      {WeftDom.Jsx.string(state.content)}
    </div>
  }
}

module Root = {
  /** `content`, the tooltip's text, shown `delay` ms after the pointer comes (at once on focus). */
  @weft.component
  let make = (~content: string, ~side: Anchored.side=#top, ~delay=500, ~children=?) => {
    let (open_, setOpen) = Weft.Hooks.useState(() => false)
    let timer = Weft.Hooks.useRef(None)
    let id = Weft.Hooks.useId()
    let cancel = () => {
      timer.current->Option.forEach(clearTimeout)
      timer.current = None
    }
    Weft.Hooks.useEffect0(() => Some(cancel))
    let show = (~now) => {
      cancel()
      if now {
        setOpen(_ => true)
      } else {
        timer.current = Some(setTimeout(() => setOpen(_ => true), delay))
      }
    }
    let hide = () => {
      cancel()
      setOpen(_ => false)
    }
    <Provider
      value={{
        open_,
        show,
        hide,
        popupId: `${id}-tooltip`,
        anchor: Overlay.anchorName(id),
        content,
        side,
      }}
    >
      {children->Option.getOr(WeftDom.Jsx.null)}
      <Popup />
    </Provider>
  }
}

module Trigger = {
  /**
  The control it labels: a button (`Button`'s look, or `IconButton`'s with a `label`, which then is
  its name, the tooltip only showing it).
  */
  @weft.component
  let make = (
    ~label: option<string>=?,
    ~variant: Button.variant=#secondary,
    ~size: Variants.size=#md,
    ~onClick=?,
    ~disabled=false,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=WeftDom.Jsx.null,
  ) => {
    let state = Weft.Hooks.useContext(context)
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
      ~disabled,
      ~onClick,
      ~id=None,
      ~style=Some(Anchored.triggerStyle(~anchor=state.anchor, style)),
      ~dataId,
      ~ariaLabel=label,
      // With a label, the tooltip only shows it: describing the button by it too would say it twice.
      ~ariaDescribedby=label->Option.isSome ? None : Some(state.popupId),
      ~ariaExpanded=None,
      ~ariaControls=None,
      ~ariaHaspopup=None,
      ~ariaPressed=None,
      ~name=None,
      ~value=None,
      ~title=None,
      ~attrs={
        onPointerEnter: _ => state.show(~now=false),
        onPointerLeave: _ => state.hide(),
        onFocus: _ => state.show(~now=true),
        onBlur: _ => state.hide(),
        onKeyDown: event =>
          if Dom.Event.key(event) == "Escape" && state.open_ {
            state.hide()
          },
      },
      ~children=switch label {
      | Some(_) => <span ariaHidden="true"> children </span>
      | None => children
      },
    )
  }
}
