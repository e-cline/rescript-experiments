/***
A form whose page shows its own errors: submitting it calls `onSubmit` (the browser's own
submitting and validation bubbles are off), and `error` (what went wrong as a whole: the server said
no) is shown at its top as an alert. Each field's own error goes in its `Field`.

```rescript
<Form onSubmit=save busy=saving error=?saveError>
  <Field label="Title" error=?titleError> <Input value=title onInput /> </Field>
  <Button type_=#submit variant=#primary busy=saving> {text("Save")} </Button>
</Form>
```

While `busy`, it's `aria-busy`, and a submit does nothing.

Interactive: its submit handler is client code, so it renders inside an entrypoint.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let form = Css.class(~layer, {display: Flex, flexDirection: Column, gap: Var(Tokens.spaceLg)})
}

@weft.component
let make = (
  ~onSubmit: option<unit => unit>=?,
  ~busy=false,
  ~error: option<string>=?,
  ~id=?,
  ~className=?,
  ~style=?,
  ~dataId=?,
  ~ariaLabel=?,
  ~ariaLabelledby=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=?,
) =>
  Host.withAttrs(
    attrs,
    <form
      ?id
      className={Host.classes([Styles.form], className)}
      ?style
      ?dataId
      ?ariaLabel
      ?ariaLabelledby
      noValidate=true
      ariaBusy=?{busy ? Some("true") : None}
      onSubmit=?{onSubmit->Option.map(onSubmit =>
        event => {
          WeftDom.Dom.Event.preventDefault(event)
          if !busy {
            onSubmit()
          }
        }
      )}
    >
      {switch error {
      | Some(error) =>
        <Alert.Root tone=#danger>
          <Alert.Description> {WeftDom.Jsx.string(error)} </Alert.Description>
        </Alert.Root>
      | None => WeftDom.Jsx.null
      }}
      {children->Option.getOr(WeftDom.Jsx.null)}
    </form>,
  )
