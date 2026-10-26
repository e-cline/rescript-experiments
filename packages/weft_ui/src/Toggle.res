/***
A button that's on or off (`aria-pressed`): a wishlist's heart, a bold button. Its label says what
it does, and stays the same either way; the pressed state says whether it's on.

```rescript
<Toggle label="Save to wishlist" pressed=saved onPressedChange=setSaved> {text("♥")} </Toggle>
```

With `label`, it's an icon toggle (square, the label naming it); without, its `children` are its
text. Without `pressed`, it keeps its own (from `defaultPressed`).

Interactive: it keeps state, so it renders inside an entrypoint.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let toggle = Css.class(
    ~layer,
    {
      selectors: [
        (
          "&[aria-pressed=\"true\"]",
          Css.style({
            color: Var(Tokens.accentSoftFg),
            backgroundColor: Var(Tokens.accentSoft),
            borderColor: Var(Tokens.accent),
          }),
        ),
      ],
    },
  )
}

/** A toggle's classes: `Button`'s, or `IconButton`'s with a `label`, then the pressed look. */
let className = (~variant: Button.variant, ~size: Variants.size, ~icon: bool) =>
  Css.cx([
    icon ? IconButton.className(~variant, ~size, ()) : Button.className(~variant, ~size, ()),
    Styles.toggle,
  ])

@weft.component
let make = (
  ~pressed: option<bool>=?,
  ~defaultPressed=false,
  ~onPressedChange: option<bool => unit>=?,
  ~label: option<string>=?,
  ~variant: Button.variant=#secondary,
  ~size: Variants.size=#md,
  ~disabled=false,
  ~id=?,
  ~className as extra=?,
  ~style=?,
  ~dataId=?,
  ~ariaDescribedby=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=WeftDom.Jsx.null,
) => {
  let (pressed, setPressed) = Controllable.use(
    ~value=pressed,
    ~defaultValue=defaultPressed,
    ~onChange=onPressedChange,
  )
  Button.render(
    ~className=Host.classes([className(~variant, ~size, ~icon=label->Option.isSome)], extra),
    ~type_=#button,
    ~busy=false,
    ~disabled,
    ~onClick=Some(_ => setPressed(!pressed)),
    ~id,
    ~style,
    ~dataId,
    ~ariaLabel=label,
    ~ariaDescribedby,
    ~ariaExpanded=None,
    ~ariaControls=None,
    ~ariaHaspopup=None,
    ~ariaPressed=Some(Host.ariaBool(pressed)),
    ~name=None,
    ~value=None,
    ~title=None,
    ~attrs,
    ~children=switch label {
    | Some(_) => <span ariaHidden="true"> children </span>
    | None => children
    },
  )
}
