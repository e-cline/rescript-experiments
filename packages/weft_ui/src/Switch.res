/***
An on/off switch with its label (`children`): a checkbox with `role="switch"`, drawn as a track and
a thumb, for a setting that applies at once (not one a form submits later: that's a `Checkbox`).

```rescript
<Switch checked=onSale onCheckedChange=setOnSale> {text("On sale only")} </Switch>
```

`dataId` is the input's.

Interactive: it uses `useId`, so it renders inside an entrypoint.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  /** The track is the input itself; the thumb its background, which slides across. */
  let track = Css.class(
    ~layer,
    {
      flexShrink: 0.,
      appearance: "none",
      boxSizing: BorderBox,
      width: Px(36),
      height: Px(20),
      margin: Zero,
      font: "inherit",
      marginTop: Raw("calc((1.5em - 20px) / 2)"),
      borderRadius: Var(Tokens.radiusFull),
      border: "2px solid transparent",
      backgroundColor: Var(Tokens.borderStrong),
      background: `radial-gradient(circle closest-side, white 0 100%, transparent 100%) 0 50% / 16px 16px no-repeat ${Tokens.value(
          Tokens.borderStrong,
        )}`,
      cursor: Raw("inherit"),
      transition: `background-position ${Tokens.value(
          Tokens.durationMedium,
        )}, background-color ${Tokens.value(Tokens.durationMedium)}`,
      focusVisible: Tokens.focusVisible(),
      checked: Css.style({
        backgroundColor: Var(Tokens.accent),
        background: `radial-gradient(circle closest-side, white 0 100%, transparent 100%) 100% 50% / 16px 16px no-repeat ${Tokens.value(
            Tokens.accent,
          )}`,
      }),
    },
  )
}

@weft.component
let make = (
  ~checked: option<bool>=?,
  ~onCheckedChange: option<bool => unit>=?,
  ~onChange=?,
  ~description: option<string>=?,
  ~name=?,
  ~value=?,
  ~disabled=false,
  ~id=?,
  ~className=?,
  ~style=?,
  ~dataId=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=?,
) => {
  let descriptionId = `${Weft.Hooks.useId()}-description`
  Choice.render(
    ~control=Host.withAttrs(
      attrs,
      <input
        type_="checkbox"
        role="switch"
        ?id
        className=Styles.track
        ?dataId
        ?checked
        onChange=?{Choice.onChange(~onChange, ~onCheckedChange)}
        ?name
        ?value
        disabled
        ariaDescribedby=?{description->Option.map(_ => descriptionId)}
      />,
    ),
    ~children,
    ~description,
    ~descriptionId,
    ~className,
    ~style,
  )
}
