/***
A group of controls with a name (`legend`): an address's fields, a filter's choices. Its
`description` and `error` work as a `Field`'s, for the group. `disabled` disables everything in it.

```rescript
<Fieldset legend="Where to?">
  <Field label="Street"> <Input ... /> </Field>
  <Field label="City"> <Input ... /> </Field>
</Fieldset>
```

Interactive: it uses `useId`, so it renders inside an entrypoint.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let fieldset = Css.class(~layer, {minWidth: Zero, margin: Zero, padding: Zero, border: "none"})
  /** What's in it, a gap apart (the description and the error are outside the gaps). */
  let items = Css.class(~layer, {display: Flex, flexDirection: Column, gap: Var(Tokens.spaceMd)})
  let legend = Css.class(
    ~layer,
    {
      padding: Zero,
      marginBlockEnd: Var(Tokens.spaceSm),
      fontSize: Var(Tokens.textMd),
      fontWeight: 600,
      color: Var(Tokens.fg),
    },
  )
  let gapSm = Css.class(~layer, {gap: Var(Tokens.spaceSm)})
  let description = Css.class(
    ~layer,
    {
      margin: Zero,
      marginBlockEnd: Var(Tokens.spaceSm),
      fontSize: Var(Tokens.textSm),
      color: Var(Tokens.fgMuted),
    },
  )
}

@weft.component
let make = (
  ~legend: string,
  ~hideLegend=false,
  ~description: option<string>=?,
  ~error: option<string>=?,
  ~disabled=false,
  ~gap: [#sm | #md]=#md,
  ~id=?,
  ~className=?,
  ~style=?,
  ~dataId=?,
  ~children=?,
) => {
  let generated = Weft.Hooks.useId()
  let descriptionId = `${generated}-description`
  let errorId = `${generated}-error`
  let describedBy = switch (description, error) {
  | (Some(_), Some(_)) => Some(`${descriptionId} ${errorId}`)
  | (Some(_), None) => Some(descriptionId)
  | (None, Some(_)) => Some(errorId)
  | (None, None) => None
  }
  <fieldset
    ?id
    className={Host.classes([Styles.fieldset], className)}
    ?style
    ?dataId
    disabled
    ariaDescribedby=?describedBy
  >
    <legend className={hideLegend ? VisuallyHidden.className : Styles.legend}>
      {WeftDom.Jsx.string(legend)}
    </legend>
    {switch description {
    | Some(description) =>
      <p id=descriptionId className=Styles.description> {WeftDom.Jsx.string(description)} </p>
    | None => WeftDom.Jsx.null
    }}
    <div className={gap == #sm ? Css.cx([Styles.items, Styles.gapSm]) : Styles.items}>
      {children->Option.getOr(WeftDom.Jsx.null)}
    </div>
    <p id=errorId className=Field.Styles.error ariaLive="polite">
      {WeftDom.Jsx.string(error->Option.getOr(""))}
    </p>
  </fieldset>
}
