@@weft.server

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Form"
      summary="A form that shows its own errors: each field's in its Field, what went wrong as a whole at its top."
    >
      <Specimen.Example caption="Submit it empty, then fill it in">
        <FormDemos.SignUp />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Field"
      summary="A labelled control, with a description and an error, which it tells the control about (its id, aria-describedby, aria-invalid)."
    >
      <Specimen.Example
        caption="Input's sizes, and a field disabled, invalid, and with its label hidden"
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
      >
        <FormDemos.Choices />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="NumberField"
      summary="A number, typed or stepped: the arrow keys step, PageUp and PageDown by ten, Home and End to the bounds."
    >
      <Specimen.Example caption="In bounds, and stepping by 0.5">
        <FormDemos.Numbers />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Toggle and ToggleGroup"
      summary="Buttons that are on or off; in a group, one Tab stop, the arrow keys moving between them."
    >
      <Specimen.Example caption="Toggles, an icon toggle, a single and a multiple group">
        <FormDemos.Toggles />
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
