@@weft.server

module Jsx = WeftDom.Jsx

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Combobox"
      summary="A text input with suggestions: the arrow keys highlight them while the focus stays in the input, Enter chooses one, Escape closes."
    >
      <Specimen.Example
        caption="Suggestions filtered as it's typed, kinds beside them"
        code={`<Field label="Fruit">
  <Combobox.Root onSelect=choose>
    <Combobox.Input value=query onInput />
    {matches == []
      ? <Combobox.Popup> <Combobox.Empty> {text("No fruit")} </Combobox.Empty> </Combobox.Popup>
      : <Combobox.Popup>
          {matches->Array.map(fruit =>
            <Combobox.Item key=fruit.id value=fruit.id> {text(fruit.name)} </Combobox.Item>
          )->Jsx.array}
        </Combobox.Popup>}
  </Combobox.Root>
</Field>`}
      >
        <DisclosureDemos.FruitSearch />
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
