/***
A button. `variant` is how much it stands out (`#primary` for the one thing to do, `#secondary`,
`#outline`, `#ghost`, `#danger`, or `#link`, a button that looks like a link), `size` how big it is.

`busy` shows a spinner in it and stops clicks while it's at it (it's `aria-disabled`, so it keeps
its focus and stays in the tab order, unlike `disabled`).

`Button.className()` gives anything else (an app's navigating link) its look.

```rescript
<Button variant=#primary type_=#submit busy=saving> {text("Save")} </Button>
```

Static: a server component can render it (without `onClick`).
*/
open WeftCss
module Jsx = WeftDom.Jsx

module Styles = {
  let layer = Tokens.layer
  let button = Css.class(
    ~layer,
    {
      display: InlineFlex,
      alignItems: Center,
      justifyContent: Center,
      gap: Var(Tokens.spaceSm),
      boxSizing: BorderBox,
      border: "1px solid transparent",
      borderRadius: Var(Tokens.radiusMd),
      font: "inherit",
      fontWeight: 500,
      lineHeight: 1.2,
      whiteSpace: Nowrap,
      textDecoration: None,
      cursor: Pointer,
      userSelect: None,
      transition: `background-color ${Tokens.value(
          Tokens.durationFast,
        )}, border-color ${Tokens.value(Tokens.durationFast)}, color ${Tokens.value(
          Tokens.durationFast,
        )}`,
      focusVisible: Tokens.focusVisible(),
      disabled: Css.style({opacity: 0.5, cursor: NotAllowed}),
      selectors: [("&[aria-disabled=\"true\"]", Css.style({cursor: Default}))],
    },
  )
  let sm = Css.class(
    ~layer,
    {
      minHeight: Var(Tokens.controlSm),
      padding: Pair(Px(0), Var(Tokens.spaceSm)),
      fontSize: Var(Tokens.textSm),
    },
  )
  let md = Css.class(
    ~layer,
    {
      minHeight: Var(Tokens.controlMd),
      padding: Pair(Px(0), Var(Tokens.spaceMd)),
      fontSize: Var(Tokens.textSm),
    },
  )
  let lg = Css.class(
    ~layer,
    {
      minHeight: Var(Tokens.controlLg),
      padding: Pair(Px(0), Var(Tokens.spaceLg)),
      fontSize: Var(Tokens.textMd),
    },
  )

  // The hover rules only apply to a button that can be pressed.
  let enabled = "&:hover:not(:disabled):not([aria-disabled=\"true\"])"

  let primary = Css.class(
    ~layer,
    {
      color: Var(Tokens.accentFg),
      backgroundColor: Var(Tokens.accent),
      selectors: [(enabled, Css.style({backgroundColor: Var(Tokens.accentHover)}))],
    },
  )
  let secondary = Css.class(
    ~layer,
    {
      color: Var(Tokens.fg),
      backgroundColor: Var(Tokens.surface),
      borderColor: Var(Tokens.border),
      selectors: [
        (
          enabled,
          Css.style({
            backgroundColor: Var(Tokens.surfaceMuted),
            borderColor: Var(Tokens.borderStrong),
          }),
        ),
      ],
    },
  )
  let outline = Css.class(
    ~layer,
    {
      color: Var(Tokens.accent),
      backgroundColor: Transparent,
      borderColor: Var(Tokens.accent),
      selectors: [(enabled, Css.style({backgroundColor: Var(Tokens.accentSoft)}))],
    },
  )
  let ghost = Css.class(
    ~layer,
    {
      color: Var(Tokens.fg),
      backgroundColor: Transparent,
      selectors: [(enabled, Css.style({backgroundColor: Var(Tokens.surfaceMuted)}))],
    },
  )
  let danger = Css.class(
    ~layer,
    {
      color: Var(Tokens.dangerFg),
      backgroundColor: Var(Tokens.danger),
      selectors: [(enabled, Css.style({backgroundColor: Var(Tokens.dangerHover)}))],
    },
  )
  let link = Css.class(
    ~layer,
    {
      minHeight: Auto,
      padding: Zero,
      color: Var(Tokens.accent),
      backgroundColor: Transparent,
      textDecoration: Underline,
      textUnderlineOffset: Em(0.2),
      selectors: [(enabled, Css.style({color: Var(Tokens.accentHover)}))],
    },
  )
  let pill = Css.class(~layer, {borderRadius: Var(Tokens.radiusFull)})
  let fullWidth = Css.class(~layer, {display: Flex, inlineSize: Pct(100.)})
  /** An icon button: square. */
  let square = Css.class(~layer, {padding: Zero, aspectRatio: "1"})
  let squareSm = Css.class(~layer, {inlineSize: Var(Tokens.controlSm)})
  let squareMd = Css.class(~layer, {inlineSize: Var(Tokens.controlMd)})
  let squareLg = Css.class(~layer, {inlineSize: Var(Tokens.controlLg)})
}

type variant = [#primary | #secondary | #outline | #ghost | #danger | #link]

/** A button's classes, for something else that should look like one (an app's link). */
let className = (
  ~variant: variant=#secondary,
  ~size: Variants.size=#md,
  ~shape: [#rounded | #pill]=#rounded,
  ~fullWidth=false,
  (),
) =>
  Css.cxOpt([
    Some(Styles.button),
    Some(
      switch size {
      | #sm => Styles.sm
      | #md => Styles.md
      | #lg => Styles.lg
      },
    ),
    Some(
      switch variant {
      | #primary => Styles.primary
      | #secondary => Styles.secondary
      | #outline => Styles.outline
      | #ghost => Styles.ghost
      | #danger => Styles.danger
      | #link => Styles.link
      },
    ),
    shape == #pill ? Some(Styles.pill) : None,
    fullWidth ? Some(Styles.fullWidth) : None,
  ])

type type_ = [#button | #submit | #reset]

/**
The `<button>` itself, which `IconButton` (and later the overlays' triggers) share: `busy` stops
`onClick` (and a submit button's submitting) while it's set.
*/
let render = (
  ~className: string,
  ~type_: type_,
  ~busy: bool,
  ~disabled: bool,
  ~onClick: option<WeftDom.Dom.event => unit>,
  ~id: option<string>,
  ~style: option<dict<string>>,
  ~dataId: option<string>,
  ~ariaLabel: option<string>,
  ~ariaDescribedby: option<string>,
  ~ariaExpanded: option<string>,
  ~ariaControls: option<string>,
  ~ariaHaspopup: option<string>,
  ~ariaPressed: option<string>,
  ~name: option<string>,
  ~value: option<string>,
  ~title: option<string>,
  ~attrs: WeftDom.DomProps.props,
  ~children: Weft.Element.t,
) =>
  Host.withAttrs(
    attrs,
    <button
      ?id
      className
      ?style
      ?dataId
      type_={(type_ :> string)}
      disabled
      ariaDisabled=?{busy ? Some("true") : None}
      ariaBusy=?{busy ? Some("true") : None}
      ?ariaLabel
      ?ariaDescribedby
      ?ariaExpanded
      ?ariaControls
      ?ariaHaspopup
      ?ariaPressed
      ?name
      ?value
      ?title
      // While busy, a click does nothing: not the handler, and not a submit button's submitting.
      onClick=?{switch (onClick, busy, type_) {
      | (Some(onClick), false, _) => Some(onClick)
      | (_, true, #submit | #reset) => Some(WeftDom.Dom.Event.preventDefault)
      | (_, true, #button) | (None, false, _) => None
      }}
    >
      {busy ? Spinner.picture(~size=#sm) : Jsx.null}
      children
    </button>,
  )

@weft.component
let make = (
  ~variant: variant=#secondary,
  ~size: Variants.size=#md,
  ~shape: [#rounded | #pill]=#rounded,
  ~fullWidth=false,
  ~type_: type_=#button,
  ~busy=false,
  ~disabled=false,
  ~onClick=?,
  ~id=?,
  ~className as extra=?,
  ~style=?,
  ~dataId=?,
  ~ariaLabel=?,
  ~ariaDescribedby=?,
  ~ariaExpanded=?,
  ~ariaControls=?,
  ~ariaHaspopup=?,
  ~ariaPressed=?,
  ~name=?,
  ~value=?,
  ~title=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=Jsx.null,
) =>
  render(
    ~className=Host.classes([className(~variant, ~size, ~shape, ~fullWidth, ())], extra),
    ~type_,
    ~busy,
    ~disabled,
    ~onClick,
    ~id,
    ~style,
    ~dataId,
    ~ariaLabel,
    ~ariaDescribedby,
    ~ariaExpanded,
    ~ariaControls,
    ~ariaHaspopup,
    ~ariaPressed,
    ~name,
    ~value,
    ~title,
    ~attrs,
    ~children,
  )
