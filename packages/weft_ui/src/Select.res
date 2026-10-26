/***
A choice from a list: the browser's own `<select>`, whose popup and keyboard are the platform's
(the most accessible, on a phone especially), with weft_ui's border and a chevron of its own.

```rescript
<Field label="Sort by">
  <Select value=sort onChange={event => setSort(Event.targetValue(event))}>
    <Select.Option value="featured"> {text("Featured")} </Select.Option>
    <Select.Option value="price-asc"> {text("Price: low to high")} </Select.Option>
  </Select>
</Field>
```

`onChange` is the DOM's `change` event: it fires when a choice is made.

Interactive: it reads its `Field`, so it renders inside an entrypoint.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  /** The select and its chevron: the chevron, drawn by CSS, doesn't take clicks. */
  let wrapper = Css.class(
    ~layer,
    {
      position: Relative,
      display: Flex,
      minWidth: Zero,
      after: Css.style({
        content: "\"\"",
        position: Absolute,
        insetInlineEnd: Var(Tokens.spaceMd),
        top: Pct(50.),
        width: Px(7),
        height: Px(7),
        marginTop: Px(-5),
        borderRight: "1.5px solid",
        borderBottom: "1.5px solid",
        borderColor: Var(Tokens.fgMuted),
        transform: "rotate(45deg)",
        pointerEvents: None,
      }),
    },
  )
  let select = Css.class(
    ~layer,
    {...Controls.base(), appearance: "none", cursor: Pointer, paddingInlineEnd: Px(32)},
  )
  let sm = Css.class(~layer, Controls.sized(#sm))
  let md = Css.class(~layer, Controls.sized(#md))
  let lg = Css.class(~layer, Controls.sized(#lg))
  // The size classes set the padding, so the end's room for the chevron comes after them.
  let room = Css.class(~layer, {paddingInlineEnd: Px(32)})
}

module Option = {
  @weft.component
  let make = (~value: string, ~disabled=?, ~children=?) => <option value ?disabled ?children />
}

@weft.component
let make = (
  ~size: Variants.size=#md,
  ~value=?,
  ~onChange=?,
  ~onBlur=?,
  ~name=?,
  ~autoComplete=?,
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
  ~children=?,
) => {
  let field = FieldContext.use()
  let invalid = invalid->Stdlib.Option.getOr(field.invalid)
  let required = required->Stdlib.Option.getOr(field.required)
  <span className=Styles.wrapper>
    {Host.withAttrs(
      attrs,
      <select
        id=?{id->Stdlib.Option.orElse(field.controlId)}
        className={Host.classes(
          [
            Styles.select,
            switch size {
            | #sm => Styles.sm
            | #md => Styles.md
            | #lg => Styles.lg
            },
            Styles.room,
          ],
          className,
        )}
        ?style
        ?dataId
        ?value
        ?onChange
        ?onBlur
        ?name
        ?autoComplete
        required
        disabled={disabled->Stdlib.Option.getOr(field.disabled)}
        ariaInvalid=?{invalid ? Some("true") : None}
        ariaRequired=?{required ? Some("true") : None}
        ?ariaLabel
        ariaDescribedby=?{FieldContext.describedBy(ariaDescribedby, field.describedBy)}
        ?children
      />,
    )}
  </span>
}
