@@weft.server

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Form"
      summary="A form that shows its own errors: each field's in its Field, what went wrong as a whole at its top."
    >
      <Specimen.Example
        caption="Submit it empty, then fill it in"
        code={`<Form onSubmit=submit error=?formError>
  <Field label="Email" description="For the receipt." error=?emailError required=true>
    <Input type_=#email value=email onInput autoComplete="email" />
  </Field>
  <Field label="About you"> <Textarea value=about onInput /> </Field>
  <Field label="Country">
    <Select value=country onChange>
      <Select.Option value="uk"> {text("United Kingdom")} </Select.Option>
    </Select>
  </Field>
  <Button type_=#submit variant=#primary> {text("Sign up")} </Button>
</Form>`}
      >
        <FormDemos.SignUp />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Field"
      summary="A labelled control, with a description and an error, which it tells the control about (its id, aria-describedby, aria-invalid)."
    >
      <Specimen.Example
        caption="Input's sizes, and a field disabled, invalid, and with its label hidden"
        code={`<Field label="Small"> <Input size=#sm /> </Field>
<Field label="Disabled" disabled=true> <Input /> </Field>
<Field label="Invalid" error="That isn't an email address."> <Input /> </Field>
<Field label="Search" hideLabel=true> <Input type_=#search placeholder="Search" /> </Field>`}
      >
        <FormDemos.States />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Checkbox, RadioGroup and Switch"
      summary="The platform's own checkboxes and radio buttons, in the accent colour; a switch is a checkbox with the switch role."
    >
      <Specimen.Example
        caption="A select-all (indeterminate while some are), radio buttons with descriptions, switches"
        code={`<Checkbox checked=all indeterminate=some onCheckedChange=setAll> {text("All")} </Checkbox>
<RadioGroup.Root legend="Delivery" value onValueChange>
  <RadioGroup.Radio value="express" description="Order by 2pm"> {text("Express")} </RadioGroup.Radio>
</RadioGroup.Root>
<Switch checked onCheckedChange> {text("Email me about orders")} </Switch>`}
      >
        <FormDemos.Choices />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="NumberField"
      summary="A number, typed or stepped: the arrow keys step, PageUp and PageDown by ten, Home and End to the bounds."
    >
      <Specimen.Example
        caption="In bounds, and stepping by 0.5"
        code={`<Field label="Quantity">
  <NumberField.Root value onValueChange min=1. max=10.>
    <NumberField.Decrement />
    <NumberField.Input />
    <NumberField.Increment />
  </NumberField.Root>
</Field>`}
      >
        <FormDemos.Numbers />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Toggle and ToggleGroup"
      summary="Buttons that are on or off; in a group, one Tab stop, the arrow keys moving between them."
    >
      <Specimen.Example
        caption="Toggles, an icon toggle, a single and a multiple group"
        code={`<Toggle pressed onPressedChange> {text("Bold")} </Toggle>
<Toggle label="Save to wishlist" variant=#ghost> {text("♥")} </Toggle>
<ToggleGroup.Root label="Size" value=[size] onValueChange>
  <ToggleGroup.Item value="s"> {text("S")} </ToggleGroup.Item>
  <ToggleGroup.Item value="m"> {text("M")} </ToggleGroup.Item>
</ToggleGroup.Root>
<ToggleGroup.Root label="Style" type_=#multiple> ... </ToggleGroup.Root>`}
      >
        <FormDemos.Toggles />
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
