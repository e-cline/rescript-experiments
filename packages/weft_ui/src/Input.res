/***
A one-line text input, in a `Field` (which labels it) or labelled some other way (`ariaLabel`).

```rescript
<Field label="Name"> <Input value=name onInput={event => setName(_ => Event.targetValue(event))} /> </Field>
```

It's controlled by `value`: set it from your state in `onInput`, which fires on every keystroke.

Interactive: it reads its `Field`, so it renders inside an entrypoint.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let input = Css.class(~layer, Controls.base())
  let sm = Css.class(~layer, Controls.sized(#sm))
  let md = Css.class(~layer, Controls.sized(#md))
  let lg = Css.class(~layer, Controls.sized(#lg))
  /** A search box: the browser's clear button keeps its place. */
  let search = Css.class(~layer, {appearance: "none"})
}

type type_ = [#text | #email | #password | #search | #tel | #url | #number]

/** An input's classes, for an input of your own. */
let className = (~size: Variants.size=#md, ()) =>
  Css.cx([
    Styles.input,
    switch size {
    | #sm => Styles.sm
    | #md => Styles.md
    | #lg => Styles.lg
    },
  ])

@weft.component
let make = (
  ~type_: type_=#text,
  ~size: Variants.size=#md,
  ~value=?,
  ~onInput=?,
  ~onChange=?,
  ~onBlur=?,
  ~onFocus=?,
  ~onKeyDown=?,
  ~name=?,
  ~placeholder=?,
  ~autoComplete=?,
  ~inputMode=?,
  ~min=?,
  ~max=?,
  ~step=?,
  ~minLength=?,
  ~maxLength=?,
  ~pattern=?,
  ~readOnly=?,
  ~autoFocus=?,
  ~invalid: option<bool>=?,
  ~required: option<bool>=?,
  ~disabled: option<bool>=?,
  ~id=?,
  ~className as extra=?,
  ~style=?,
  ~dataId=?,
  ~ariaLabel=?,
  ~ariaDescribedby=?,
  ~attrs: WeftDom.DomProps.props={},
) => {
  let field = FieldContext.use()
  let invalid = invalid->Option.getOr(field.invalid)
  let required = required->Option.getOr(field.required)
  <input
    {...attrs}
    id=?{id->Option.orElse(field.controlId)}
    type_={(type_ :> string)}
    className={Host.classes(
      type_ == #search ? [className(~size, ()), Styles.search] : [className(~size, ())],
      extra,
    )}
    ?style
    ?dataId
    ?value
    ?onInput
    ?onChange
    ?onBlur
    ?onFocus
    ?onKeyDown
    ?name
    ?placeholder
    ?autoComplete
    ?inputMode
    ?min
    ?max
    ?step
    ?minLength
    ?maxLength
    ?pattern
    ?readOnly
    ?autoFocus
    required
    disabled={disabled->Option.getOr(field.disabled)}
    ariaInvalid=?{invalid ? Some("true") : None}
    ariaRequired=?{required ? Some("true") : None}
    ?ariaLabel
    ariaDescribedby=?{FieldContext.describedBy(ariaDescribedby, field.describedBy)}
  />
}
