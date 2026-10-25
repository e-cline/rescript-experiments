/***
A square button with an icon (or a symbol, "×") and no text: `label` names it for assistive
technology, so it's required. The icon itself is hidden from it.

```rescript
<IconButton label="Dismiss" variant=#ghost onClick=dismiss> {text("×")} </IconButton>
```

Static: a server component can render it (without `onClick`).
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let icon = Css.class(~layer, {display: InlineFlex, lineHeight: 1., fontSize: Em(1.25)})
}

/** An icon button's classes, for something else that should look like one. */
let className = (
  ~variant: Button.variant=#ghost,
  ~size: Variants.size=#md,
  ~shape: [#rounded | #pill]=#rounded,
  (),
) =>
  Css.cx([
    Button.className(~variant, ~size, ~shape, ()),
    Button.Styles.square,
    switch size {
    | #sm => Button.Styles.squareSm
    | #md => Button.Styles.squareMd
    | #lg => Button.Styles.squareLg
    },
  ])

@weft.component
let make = (
  ~label: string,
  ~variant: Button.variant=#ghost,
  ~size: Variants.size=#md,
  ~shape: [#rounded | #pill]=#rounded,
  ~type_: Button.type_=#button,
  ~busy=false,
  ~disabled=false,
  ~onClick=?,
  ~id=?,
  ~className as extra=?,
  ~style=?,
  ~dataId=?,
  ~ariaDescribedby=?,
  ~ariaExpanded=?,
  ~ariaControls=?,
  ~ariaHaspopup=?,
  ~ariaPressed=?,
  ~title=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=WeftDom.Jsx.null,
) =>
  Button.render(
    ~className=Host.classes([className(~variant, ~size, ~shape, ())], extra),
    ~type_,
    ~busy,
    ~disabled,
    ~onClick,
    ~id,
    ~style,
    ~dataId,
    ~ariaLabel=Some(label),
    ~ariaDescribedby,
    ~ariaExpanded,
    ~ariaControls,
    ~ariaHaspopup,
    ~ariaPressed,
    ~name=None,
    ~value=None,
    ~title,
    ~attrs,
    ~children=busy
      ? WeftDom.Jsx.null
      : <span className=Styles.icon ariaHidden="true"> children </span>,
  )
