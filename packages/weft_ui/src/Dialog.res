/***
A modal dialog: the browser's `<dialog>`, opened with `showModal()`, so it's in the top layer, the
rest of the page is inert, Escape closes it, and the focus stays in it. When it closes, the focus
goes back to what opened it.

```rescript
<Dialog.Root>
  <Dialog.Trigger> {text("Sign in")} </Dialog.Trigger>
  <Dialog.Popup>
    <Dialog.Title> {text("Sign in")} </Dialog.Title>
    <Dialog.Description> {text("With your name: it's a demo.")} </Dialog.Description>
    ...
    <Dialog.Footer> <Dialog.Close> {text("Cancel")} </Dialog.Close> </Dialog.Footer>
  </Dialog.Popup>
</Dialog.Root>
```

- **Open state** is the `Root`'s own (from `defaultOpen`), or controlled: `open`, with
  `onOpenChange` told when it opens or closes (a trigger, a close button, Escape, a click outside).
- **The focus** goes to the first focusable element in the popup as it opens (or one with
  `autoFocus`).
- **A click outside** (on its backdrop) closes it, unless `dismissible=false` (an `AlertDialog`).
- **It's named by its `Title`** (or the popup's `ariaLabel`), and described by its
  `Description`, if it has one.

Interactive: it keeps state, so it renders inside an entrypoint (`DialogEntry` is one ready-made).
*/
open WeftCss

module Dom = WeftDom.Dom

module Styles = {
  let layer = Tokens.layer
  let popup = Css.class(
    ~layer,
    {
      boxSizing: BorderBox,
      inlineSize: Raw("calc(100% - 32px)"),
      maxBlockSize: Raw("calc(100dvh - 32px)"),
      padding: Zero,
      border: "none",
      borderRadius: Var(Tokens.radiusLg),
      color: Var(Tokens.fg),
      backgroundColor: Var(Tokens.surface),
      boxShadow: Tokens.value(Tokens.shadowLg),
      overscrollBehavior: "contain",
      selectors: [
        ("&::backdrop", Css.style({backgroundColor: Rgba(0, 0, 0, 0.4)})),
        (
          "&[open]",
          Css.style({
            animation: `${Tokens.value(Tokens.durationMedium)} ease-out both`,
          }),
        ),
      ],
    },
  )
  let fadeIn = Css.keyframes(
    ~layer,
    [
      Css.frame(~at="from", {opacity: 0., transform: "translateY(8px) scale(0.98)"}),
      Css.frame(~at="to", {opacity: 1., transform: "none"}),
    ],
  )
  let animated = Css.class(~layer, {selectors: [("&[open]", Css.style({animationName: fadeIn}))]})
  let sm = Css.class(~layer, {maxInlineSize: Px(400)})
  let md = Css.class(~layer, {maxInlineSize: Px(520)})
  let lg = Css.class(~layer, {maxInlineSize: Px(720)})
  /** The popup's content: it fills the dialog, so a click on the dialog itself is on its backdrop. */
  let content = Css.class(
    ~layer,
    {
      display: Flex,
      flexDirection: Column,
      gap: Var(Tokens.spaceMd),
      padding: Var(Tokens.spaceXl),
      minBlockSize: Pct(100.),
      boxSizing: BorderBox,
    },
  )
  let title = Css.class(
    ~layer,
    {margin: Zero, fontSize: Var(Tokens.textLg), fontWeight: 600, lineHeight: 1.3},
  )
  let description = Css.class(
    ~layer,
    {margin: Zero, fontSize: Var(Tokens.textSm), color: Var(Tokens.fgMuted)},
  )
  let footer = Css.class(
    ~layer,
    {
      display: Flex,
      flexWrap: Wrap,
      justifyContent: FlexEnd,
      gap: Var(Tokens.spaceSm),
      marginBlockStart: Var(Tokens.spaceSm),
    },
  )
  // A drawer: the popup pinned to one side of the window, its full height (or width).
  let side = Css.class(
    ~layer,
    {
      margin: Zero,
      borderRadius: Zero,
      maxBlockSize: Raw("100dvh"),
      maxInlineSize: Raw("min(400px, 100% - 32px)"),
      blockSize: Raw("100dvh"),
      inlineSize: Raw("min(400px, 100% - 32px)"),
    },
  )
  let start = Css.class(~layer, {insetInlineStart: Zero, insetInlineEnd: Auto})
  let end_ = Css.class(~layer, {insetInlineEnd: Zero, insetInlineStart: Auto})
  let slideIn = Css.keyframes(
    ~layer,
    [Css.frame(~at="from", {translate: "var(--weft-ui-drawer-from, 100%) 0"})],
  )
  let slideFromEnd = Css.class(
    ~layer,
    {selectors: [("&[open]", Css.style({animationName: slideIn}))]},
  )
}

type state = {
  open_: bool,
  setOpen: bool => unit,
  popupId: string,
  titleId: string,
  descriptionId: string,
  hasDescription: bool,
  setHasDescription: bool => unit,
  trigger: Overlay.ref,
}

let context = Weft.Context.make({
  open_: false,
  setOpen: _ => (),
  popupId: "",
  titleId: "",
  descriptionId: "",
  hasDescription: false,
  setHasDescription: _ => (),
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
    ~children=?,
  ) => {
    let (current, setOpen) = Controllable.use(
      ~value=open_,
      ~defaultValue=defaultOpen,
      ~onChange=onOpenChange,
    )
    let id = Weft.Hooks.useId()
    let (hasDescription, setHasDescription) = Weft.Hooks.useState(() => false)
    let trigger = Weft.Hooks.useRef(Nullable.null)
    <Provider
      value={{
        open_: current,
        setOpen: next => next != current ? setOpen(next) : (),
        popupId: `${id}-popup`,
        titleId: `${id}-title`,
        descriptionId: `${id}-description`,
        hasDescription,
        setHasDescription: has => setHasDescription(_ => has),
        trigger,
      }}
    >
      {children->Option.getOr(WeftDom.Jsx.null)}
    </Provider>
  }
}

/** A trigger's button: `Button`'s look (or `IconButton`'s, with a `label`), opening `state`'s popup. */
let trigger = (
  ~state: state,
  ~haspopup: string,
  ~variant: Button.variant,
  ~size: Variants.size,
  ~label: option<string>,
  ~className: option<string>,
  ~dataId: option<string>,
  ~onClick: option<Dom.event => unit>,
  ~attrs: WeftDom.DomProps.props,
  ~children: Weft.Element.t,
) =>
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
    ~onClick,
    ~id=None,
    ~style=None,
    ~dataId,
    ~ariaLabel=label,
    ~ariaDescribedby=None,
    ~ariaExpanded=Some(Host.ariaBool(state.open_)),
    ~ariaControls=Some(state.popupId),
    ~ariaHaspopup=Some(haspopup),
    ~ariaPressed=None,
    ~name=None,
    ~value=None,
    ~title=None,
    ~attrs={...attrs, ref: state.trigger},
    ~children=switch label {
    | Some(_) => <span ariaHidden="true"> children </span>
    | None => children
    },
  )

module Trigger = {
  /** The button that opens the dialog. With `label`, it's an icon button that `label` names. */
  @weft.component
  let make = (
    ~variant: Button.variant=#secondary,
    ~size: Variants.size=#md,
    ~label: option<string>=?,
    ~className=?,
    ~dataId=?,
    ~attrs: WeftDom.DomProps.props={},
    ~children=WeftDom.Jsx.null,
  ) => {
    let state = use()
    trigger(
      ~state,
      ~haspopup="dialog",
      ~variant,
      ~size,
      ~label,
      ~className,
      ~dataId,
      ~onClick=Some(_ => state.setOpen(true)),
      ~attrs,
      ~children,
    )
  }
}

type placement = [#center | #start | #end]

/**
The popup itself, for `Dialog`, `AlertDialog` and `Drawer`: a `<dialog>` that `showModal()` opens
while the state is open, and whose closing (by anything) closes the state, and puts the focus back.
*/
let popup = (
  ~state: state,
  ~ref: Overlay.ref,
  ~size: [#sm | #md | #lg],
  ~placement: placement,
  ~role: option<string>,
  ~dismissible: bool,
  ~ariaLabel: option<string>,
  ~className: option<string>,
  ~style: option<dict<string>>,
  ~dataId: option<string>,
  ~children: Weft.Element.t,
) =>
  <dialog
    ref
    id=state.popupId
    className={Host.classes(
      switch placement {
      | #center => [
          Styles.popup,
          Styles.animated,
          switch size {
          | #sm => Styles.sm
          | #md => Styles.md
          | #lg => Styles.lg
          },
        ]
      | #start => [Styles.popup, Styles.side, Styles.start, Styles.slideFromEnd]
      | #end => [Styles.popup, Styles.side, Styles.end_, Styles.slideFromEnd]
      },
      className,
    )}
    style=?{switch (placement, style) {
    | (#start, _) => Some(Host.style(dict{"--weft-ui-drawer-from": "-100%"}, style))
    | (_, style) => style
    }}
    ?dataId
    ?role
    ariaLabelledby=?{ariaLabel->Option.isSome ? None : Some(state.titleId)}
    ?ariaLabel
    ariaDescribedby=?{state.hasDescription ? Some(state.descriptionId) : None}
    onClose={_ => {
      state.setOpen(false)
      Overlay.focusRef(state.trigger)
    }}
    onClick={event =>
      // The content fills the dialog, so a click on the dialog itself is on its backdrop.
      if dismissible && Dom.Event.target(event) === Dom.Event.currentTarget(event) {
        state.setOpen(false)
      }}
  >
    <div className=Styles.content> children </div>
  </dialog>

/** Opens and closes `ref`'s `<dialog>` as `open_` says. */
let useModal = (ref: Overlay.ref, open_: bool) => Weft.Hooks.useLayoutEffect1(() => {
    ref.current->Nullable.forEach(dialog =>
      if open_ && !Dom.Dialog.isOpen(dialog) {
        Dom.Dialog.showModal(dialog)
      } else if !open_ && Dom.Dialog.isOpen(dialog) {
        Dom.Dialog.close(dialog)
      }
    )
    None
  }, [open_])

module Popup = {
  @weft.component
  let make = (
    ~size: [#sm | #md | #lg]=#md,
    ~dismissible=true,
    ~ariaLabel=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=WeftDom.Jsx.null,
  ) => {
    let state = use()
    let ref = Weft.Hooks.useRef(Nullable.null)
    useModal(ref, state.open_)
    popup(
      ~state,
      ~ref,
      ~size,
      ~placement=#center,
      ~role=None,
      ~dismissible,
      ~ariaLabel,
      ~className,
      ~style,
      ~dataId,
      ~children,
    )
  }
}

module Title = {
  @weft.component
  let make = (~level: Variants.level=#h2, ~className=?, ~dataId=?, ~children=?) => {
    let state = use()
    Host.element(
      Variants.levelTag(level),
      {id: state.titleId, className: Host.classes([Styles.title], className), ?dataId, ?children},
    )
  }
}

module Description = {
  @weft.component
  let make = (~className=?, ~dataId=?, ~children=?) => {
    let state = use()
    Weft.Hooks.useLayoutEffect0(() => {
      state.setHasDescription(true)
      Some(() => state.setHasDescription(false))
    })
    <p
      id=state.descriptionId
      className={Host.classes([Styles.description], className)}
      ?dataId
      ?children
    />
  }
}

module Footer = {
  /** The dialog's actions, at its end. */
  @weft.component
  let make = (~className=?, ~dataId=?, ~children=?) =>
    <div className={Host.classes([Styles.footer], className)} ?dataId ?children />
}

module Close = {
  /** A button that closes the dialog (after `onClick`, if it has one). With `label`, an icon button. */
  @weft.component
  let make = (
    ~variant: Button.variant=#secondary,
    ~size: Variants.size=#md,
    ~label: option<string>=?,
    ~onClick: option<Dom.event => unit>=?,
    ~autoFocus=?,
    ~className=?,
    ~dataId=?,
    ~children=WeftDom.Jsx.null,
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
      ~onClick=Some(
        event => {
          onClick->Option.forEach(onClick => onClick(event))
          state.setOpen(false)
        },
      ),
      ~id=None,
      ~style=None,
      ~dataId,
      ~ariaLabel=label,
      ~ariaDescribedby=None,
      ~ariaExpanded=None,
      ~ariaControls=None,
      ~ariaHaspopup=None,
      ~ariaPressed=None,
      ~name=None,
      ~value=None,
      ~title=None,
      ~attrs={autoFocus: ?autoFocus},
      ~children=switch label {
      | Some(_) => <span ariaHidden="true"> children </span>
      | None => children
      },
    )
  }
}
