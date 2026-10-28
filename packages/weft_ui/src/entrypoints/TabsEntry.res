/***
Tabs a server component can render as they are: a tab for each of `labels`, showing its panel from
`panels` (server-rendered, in the same order). The selection is its own, from `defaultIndex`. For
anything more (controlled, tabs with more than text), use `Tabs` in an entrypoint of the app's.

```rescript
<TabsEntry label="Product" labels=["Details", "Reviews"] panels=[<Details />, <Reviews />] />
```

Each tab's and panel's `data-id` is `dataId`'s, with `-tab-<index>` or `-panel-<index>` after it.
*/

module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = (
  ~labels: array<string>,
  ~panels: array<Weft.Element.t>,
  ~label: option<string>=?,
  ~defaultIndex=0,
  ~orientation: Variants.orientation=#horizontal,
  ~variant: Tabs.variant=#underline,
  ~dataId: option<string>=?,
) => {
  let part = (kind, index) => dataId->Option.map(id => `${id}-${kind}-${Int.toString(index)}`)
  <Tabs.Root defaultValue={Int.toString(defaultIndex)} orientation variant ?dataId>
    <Tabs.List ?label>
      {labels
      ->Array.mapWithIndex((text, index) =>
        <Tabs.Tab
          key={Int.toString(index)} value={Int.toString(index)} dataId=?{part("tab", index)}
        >
          {Jsx.string(text)}
        </Tabs.Tab>
      )
      ->Jsx.array}
    </Tabs.List>
    {panels
    ->Array.mapWithIndex((panel, index) =>
      <Tabs.Panel
        key={Int.toString(index)} value={Int.toString(index)} dataId=?{part("panel", index)}
      >
        panel
      </Tabs.Panel>
    )
    ->Jsx.array}
  </Tabs.Root>
}
