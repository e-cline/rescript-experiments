/*** The disclosure and search pages' interactive examples. */

module Ui = WeftUi
module Jsx = WeftDom.Jsx

let text = Jsx.string

module Settings = {
  /** Vertical tabs, selected only on Enter or Space (manual activation), in pills. */
  @weft.component({kind: Entrypoint})
  let make = () =>
    <Ui.Tabs.Root defaultValue="profile" orientation=#vertical variant=#pills activation=#manual>
      <Ui.Tabs.List label="Settings">
        <Ui.Tabs.Tab value="profile"> {text("Profile")} </Ui.Tabs.Tab>
        <Ui.Tabs.Tab value="notifications"> {text("Notifications")} </Ui.Tabs.Tab>
        <Ui.Tabs.Tab value="billing" disabled=true> {text("Billing")} </Ui.Tabs.Tab>
        <Ui.Tabs.Tab value="security"> {text("Security")} </Ui.Tabs.Tab>
      </Ui.Tabs.List>
      <Ui.Tabs.Panel value="profile">
        <Ui.Text> {text("Your name and photo.")} </Ui.Text>
      </Ui.Tabs.Panel>
      <Ui.Tabs.Panel value="notifications">
        <Ui.Text> {text("What we email you about.")} </Ui.Text>
      </Ui.Tabs.Panel>
      <Ui.Tabs.Panel value="billing">
        <Ui.Text> {text("Cards and invoices.")} </Ui.Text>
      </Ui.Tabs.Panel>
      <Ui.Tabs.Panel value="security">
        <Ui.Text> {text("Passwords and sessions.")} </Ui.Text>
      </Ui.Tabs.Panel>
    </Ui.Tabs.Root>
}

module FruitSearch = {
  /** A combobox over a list filtered as it's typed, with a status saying what was chosen. */
  let fruit = [
    ("apple", "Apple", "Pome"),
    ("apricot", "Apricot", "Stone fruit"),
    ("banana", "Banana", "Berry"),
    ("blackberry", "Blackberry", "Aggregate"),
    ("blueberry", "Blueberry", "Berry"),
    ("cherry", "Cherry", "Stone fruit"),
    ("grape", "Grape", "Berry"),
    ("lemon", "Lemon", "Citrus"),
    ("lime", "Lime", "Citrus"),
    ("mango", "Mango", "Stone fruit"),
    ("orange", "Orange", "Citrus"),
    ("peach", "Peach", "Stone fruit"),
    ("pear", "Pear", "Pome"),
    ("plum", "Plum", "Stone fruit"),
  ]

  @weft.component({kind: Entrypoint})
  let make = () => {
    let (query, setQuery) = Weft.Hooks.useState(() => "")
    let (chosen, setChosen) = Weft.Hooks.useState(() => None)
    let needle = query->String.trim->String.toLowerCase
    let found =
      needle == ""
        ? []
        : fruit->Array.filter(((_, name, _)) => name->String.toLowerCase->String.includes(needle))
    <Ui.Stack gap=#md>
      <Ui.Field label="Fruit" description="Type a letter or two, then use the arrow keys.">
        <Ui.Combobox.Root
          onSelect={slug => {
            setChosen(_ => Some(slug))
            fruit
            ->Array.find(((id, _, _)) => id == slug)
            ->Option.forEach(((_, name, _)) => setQuery(_ => name))
          }}
        >
          <Ui.Combobox.Input
            dataId="fruit"
            value=query
            placeholder="Search fruit"
            onInput={event => setQuery(_ => WeftDom.Dom.Event.targetValue(event))}
          />
          {needle == ""
            ? Jsx.null
            : <Ui.Combobox.Popup dataId="fruit-list">
                {found == []
                  ? <Ui.Combobox.Empty> {text("No fruit matches")} </Ui.Combobox.Empty>
                  : found
                    ->Array.map(((id, name, kind)) =>
                      <Ui.Combobox.Item key=id value=id>
                        <span> {text(name)} </span>
                        <Ui.Text as_=#span tone=#muted size=#xs> {text(kind)} </Ui.Text>
                      </Ui.Combobox.Item>
                    )
                    ->Jsx.array}
              </Ui.Combobox.Popup>}
        </Ui.Combobox.Root>
      </Ui.Field>
      <Ui.Text tone=#muted size=#sm role="status" dataId="fruit-chosen">
        {text(chosen->Option.mapOr("Nothing chosen yet", slug => `Chose: ${slug}`))}
      </Ui.Text>
    </Ui.Stack>
  }
}
