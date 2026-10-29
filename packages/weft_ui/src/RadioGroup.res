/***
One choice of a few, all shown: native radio buttons sharing a `name`, in a `Fieldset` (whose
legend names the group), so the arrow keys move between them, as the platform's do.

```rescript
<RadioGroup.Root legend="Delivery" value=delivery onValueChange=setDelivery>
  <RadioGroup.Radio value="standard"> {text("Standard (3–5 days)")} </RadioGroup.Radio>
  <RadioGroup.Radio value="express" description="Order by 2pm"> {text("Express")} </RadioGroup.Radio>
</RadioGroup.Root>
```

Without `value`, it keeps its own (from `defaultValue`). Each radio's `dataId` is its input's.

Interactive: it uses context and `useId`, so it renders inside an entrypoint.
*/
open WeftCss
module Jsx = WeftDom.Jsx

module Styles = {
  let layer = Tokens.layer
  let radio = Css.class(
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
  let items = Css.class(~layer, {display: Flex, flexDirection: Column, gap: Var(Tokens.spaceSm)})
  let horizontal = Css.class(
    ~layer,
    {flexDirection: Row, flexWrap: Wrap, columnGap: Var(Tokens.spaceLg)},
  )
}

type group = {name: string, value: option<string>, select: string => unit}

let context = Weft.Context.make({name: "", value: None, select: _ => ()})

module Provider = {
  let make = Weft.Context.provider(context)
}

module Root = {
  @weft.component
  let make = (
    ~legend: string,
    ~hideLegend=false,
    ~value: option<string>=?,
    ~defaultValue: option<string>=?,
    ~onValueChange: option<string => unit>=?,
    ~name: option<string>=?,
    ~orientation: Variants.orientation=#vertical,
    ~description=?,
    ~error=?,
    ~disabled=false,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=?,
  ) => {
    let generated = Weft.Hooks.useId()
    let (current, select) = Controllable.use(
      ~value=value->Option.map(value => Some(value)),
      ~defaultValue,
      ~onChange=onValueChange->Option.map(onValueChange =>
        value => value->Option.forEach(onValueChange)
      ),
    )
    let group = {
      name: name->Option.getOr(`${generated}-radio`),
      value: current,
      select: value => select(Some(value)),
    }
    <Fieldset legend hideLegend ?description ?error disabled ?id ?className ?style ?dataId gap=#sm>
      <Provider value=group>
        <div
          className={orientation == #horizontal
            ? Css.cx([Styles.items, Styles.horizontal])
            : Styles.items}
        >
          {children->Option.getOr(Jsx.null)}
        </div>
      </Provider>
    </Fieldset>
  }
}

module Radio = {
  @weft.component
  let make = (
    ~value: string,
    ~description: option<string>=?,
    ~disabled=false,
    ~id=?,
    ~className=?,
    ~dataId=?,
    ~children=?,
  ) => {
    let group = Weft.Hooks.useContext(context)
    let descriptionId = `${Weft.Hooks.useId()}-description`
    Choice.render(
      ~control=<input
        type_="radio"
        ?id
        className=Styles.radio
        ?dataId
        name=group.name
        value
        checked=?{group.value->Option.map(selected => selected == value)}
        onChange={_ => group.select(value)}
        disabled
        ariaDescribedby=?{description->Option.map(_ => descriptionId)}
      />,
      ~children,
      ~description,
      ~descriptionId,
      ~className,
      ~style=None,
    )
  }
}
