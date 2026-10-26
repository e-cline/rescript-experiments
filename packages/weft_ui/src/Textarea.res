/***
A multi-line text input, in a `Field` (which labels it). Controlled by `value`, as `Input` is; it
grows only when the person drags its corner (`resize: vertical`).

Interactive: it reads its `Field`, so it renders inside an entrypoint.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let textarea = Css.class(
    ~layer,
    {
      ...Controls.base(),
      padding: Pair(Var(Tokens.spaceSm), Var(Tokens.spaceMd)),
      resize: "vertical",
      minHeight: Raw("calc(2lh + 18px)"),
    },
  )
}

@weft.component
let make = (
  ~rows=3,
  ~value=?,
  ~onInput=?,
  ~onChange=?,
  ~onBlur=?,
  ~onKeyDown=?,
  ~name=?,
  ~placeholder=?,
  ~maxLength=?,
  ~readOnly=?,
  ~autoFocus=?,
  ~invalid: option<bool>=?,
  ~required: option<bool>=?,
  ~disabled: option<bool>=?,
  ~id=?,
  ~className=?,
  ~style=?,
  ~dataId=?,
  ~ariaLabel=?,
  ~ariaDescribedby=?,
  ~attrs: WeftDom.DomProps.props={},
) => {
  let field = FieldContext.use()
  let invalid = invalid->Option.getOr(field.invalid)
  let required = required->Option.getOr(field.required)
  Host.withAttrs(
    attrs,
    <textarea
      id=?{id->Option.orElse(field.controlId)}
      rows
      className={Host.classes([Styles.textarea], className)}
      ?style
      ?dataId
      ?value
      ?onInput
      ?onChange
      ?onBlur
      ?onKeyDown
      ?name
      ?placeholder
      ?maxLength
      ?readOnly
      ?autoFocus
      required
      disabled={disabled->Option.getOr(field.disabled)}
      ariaInvalid=?{invalid ? Some("true") : None}
      ariaRequired=?{required ? Some("true") : None}
      ?ariaLabel
      ariaDescribedby=?{FieldContext.describedBy(ariaDescribedby, field.describedBy)}
    />,
  )
}
