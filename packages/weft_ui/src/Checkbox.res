/***
A checkbox with its label (`children`), and a description under it if there's one: the browser's
own `<input type="checkbox">`, in the accent colour, so its keyboard and states are the platform's.

```rescript
<Checkbox checked=onSale onCheckedChange=setOnSale> {text("On sale")} </Checkbox>
```

Without `checked`, it keeps its own state. `indeterminate` shows it as partly checked (a "select
all" over some of its items). `dataId` is the input's.

Interactive: it uses `useId` (and a layout effect, for `indeterminate`), so it renders inside an
entrypoint.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let box = Css.class(
    ~layer,
    {
      flexShrink: 0.,
      width: Px(16),
      height: Px(16),
      margin: Zero,
      font: "inherit",
      marginTop: Raw("calc((1.5em - 16px) / 2)"),
      accentColor: Var(Tokens.accent),
      cursor: Raw("inherit"),
      focusVisible: Tokens.focusVisible(),
    },
  )
}

@weft.component
let make = (
  ~checked: option<bool>=?,
  ~onCheckedChange: option<bool => unit>=?,
  ~onChange=?,
  ~indeterminate=false,
  ~description: option<string>=?,
  ~name=?,
  ~value=?,
  ~required=false,
  ~disabled=false,
  ~id=?,
  ~className=?,
  ~style=?,
  ~dataId=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=?,
) => {
  let descriptionId = `${Weft.Hooks.useId()}-description`
  let ref = Weft.Hooks.useRef(Nullable.null)
  Weft.Hooks.useLayoutEffect1(() => {
    ref.current->Nullable.forEach(input =>
      WeftDom.Dom.setProperty(input, "indeterminate", WeftDom.DomProps.fromBool(indeterminate))
    )
    None
  }, [indeterminate])
  Choice.render(
    ~control=<input
      {...attrs}
      ref
      type_="checkbox"
      ?id
      className=Styles.box
      ?dataId
      ?checked
      onChange=?{Choice.onChange(~onChange, ~onCheckedChange)}
      ?name
      ?value
      required
      disabled
      ariaChecked=?{indeterminate ? Some("mixed") : None}
      ariaDescribedby=?{description->Option.map(_ => descriptionId)}
    />,
    ~children,
    ~description,
    ~descriptionId,
    ~className,
    ~style,
  )
}
