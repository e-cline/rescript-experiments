/***
A labelled form control: its label, the control (an `Input`, `Textarea`, `Select` or
`NumberField`, given as `children`), a description, and an error.

```rescript
<Field label="Email" description="We'll send the receipt here." error=?emailError required=true>
  <Input type_=#email value=email onInput autoComplete="email" />
</Field>
```

The control in it gets its `id` (the label's `for`), an `aria-describedby` naming the description
and, once there is one, the error, and `aria-invalid`, `required` and `disabled` as the field has
them. The error's region is always there, and polite, so a new error is read out when it appears.

`hideLabel` keeps the label for assistive technology only (a search box with a placeholder and a
button saying what it is).

Interactive: it uses `useId`, so it renders inside an entrypoint.
*/
open WeftCss
module Jsx = WeftDom.Jsx

module Styles = {
  let layer = Tokens.layer
  let field = Css.class(~layer, {display: Flex, flexDirection: Column, minWidth: Zero})
  let label = Css.class(
    ~layer,
    {
      fontSize: Var(Tokens.textSm),
      fontWeight: 500,
      color: Var(Tokens.fg),
      marginBlockEnd: Var(Tokens.spaceXs),
    },
  )
  let required = Css.class(~layer, {color: Var(Tokens.danger), marginInlineStart: Px(2)})
  let description = Css.class(
    ~layer,
    {
      margin: Zero,
      marginBlockStart: Var(Tokens.spaceXs),
      fontSize: Var(Tokens.textSm),
      color: Var(Tokens.fgMuted),
    },
  )
  let error = Css.class(
    ~layer,
    {
      margin: Zero,
      marginBlockStart: Var(Tokens.spaceXs),
      fontSize: Var(Tokens.textSm),
      color: Var(Tokens.danger),
      selectors: [("&:empty", Css.style({marginBlockStart: Zero}))],
    },
  )
}

@weft.component
let make = (
  ~label: string,
  ~hideLabel=false,
  ~description: option<string>=?,
  ~error: option<string>=?,
  ~required=false,
  ~disabled=false,
  ~id: option<string>=?,
  ~className=?,
  ~style=?,
  ~dataId=?,
  ~children,
) => {
  let generated = Weft.Hooks.useId()
  let controlId = id->Option.getOr(`${generated}-control`)
  let descriptionId = `${generated}-description`
  let errorId = `${generated}-error`
  let invalid = error->Option.isSome
  let describedBy = switch (description, invalid) {
  | (Some(_), true) => Some(`${descriptionId} ${errorId}`)
  | (Some(_), false) => Some(descriptionId)
  | (None, true) => Some(errorId)
  | (None, false) => None
  }
  let value: FieldContext.t = {
    controlId: Some(controlId),
    describedBy,
    invalid,
    required,
    disabled,
  }
  <div className={Host.classes([Styles.field], className)} ?style ?dataId>
    <label htmlFor=controlId className={hideLabel ? VisuallyHidden.className : Styles.label}>
      {Jsx.string(label)}
      {required
        ? <span className=Styles.required ariaHidden="true"> {Jsx.string("*")} </span>
        : Jsx.null}
    </label>
    <FieldContext.Provider value> children </FieldContext.Provider>
    {switch description {
    | Some(description) =>
      <p id=descriptionId className=Styles.description> {Jsx.string(description)} </p>
    | None => Jsx.null
    }}
    <p id=errorId className=Styles.error ariaLive="polite">
      {Jsx.string(error->Option.getOr(""))}
    </p>
  </div>
}

/** What the field tells its control, for a control of your own. */
let use = FieldContext.use
