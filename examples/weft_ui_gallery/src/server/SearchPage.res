@@weft.server

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Combobox"
      summary="A text input with suggestions: the arrow keys highlight them while the focus stays in the input, Enter chooses one, Escape closes."
    >
      <Specimen.Example caption="Suggestions filtered as it's typed, kinds beside them">
        <DisclosureDemos.FruitSearch />
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
