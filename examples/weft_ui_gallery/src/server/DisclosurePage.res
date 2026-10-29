@@weft.server

module Ui = WeftUi
module Jsx = WeftDom.Jsx

let text = Jsx.string

let questions = [
  ("Is it true to size?", "Yes: most shoppers take their usual size."),
  ("Can I return it?", "Within 30 days, unworn, with its tags."),
  ("How do I wash it?", "By hand, cold, and dry it flat."),
]

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Tabs"
      summary="A tab per panel: one Tab stop, the arrow keys moving (and selecting) along the list, every panel kept mounted."
    >
      <Specimen.Example
        caption="TabsEntry, rendered by this server component, its panels the server's"
        code={`<TabsEntry
  label="Product"
  labels=["Details", "Materials", "Reviews"]
  panels=[<Details />, <Materials />, <Reviews />]
/>`}
      >
        <Ui.TabsEntry
          label="Product"
          labels=["Details", "Materials", "Reviews"]
          dataId="product-tabs"
          panels=[
            <Ui.Text> {text("A long, warm scarf in hand-dyed merino.")} </Ui.Text>,
            <Ui.Text> {text("100% merino wool. Dyed by hand in small batches.")} </Ui.Text>,
            <Ui.Text> {text("4.8 out of 5, from 32 reviews.")} </Ui.Text>,
          ]
        />
      </Specimen.Example>
      <Specimen.Example
        caption="Vertical pills, activated by Enter or Space (manual), one disabled"
        code={`<Tabs.Root defaultValue="profile" orientation=#vertical variant=#pills activation=#manual>
  <Tabs.List label="Settings">
    <Tabs.Tab value="profile"> {text("Profile")} </Tabs.Tab>
    <Tabs.Tab value="billing" disabled=true> {text("Billing")} </Tabs.Tab>
  </Tabs.List>
  <Tabs.Panel value="profile"> ... </Tabs.Panel>
  <Tabs.Panel value="billing"> ... </Tabs.Panel>
</Tabs.Root>`}
      >
        <DisclosureDemos.Settings />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Accordion"
      summary="Sections that open and close, divided: the browser's details, so they work before (or without) JavaScript."
    >
      <Specimen.Example
        caption="One open at a time (the items share a name), the first open"
        code={`<Accordion.Root>
  <Accordion.Item name="faq" defaultOpen=true>
    <Accordion.Trigger> {text("Is it true to size?")} </Accordion.Trigger>
    <Accordion.Panel> {text("Yes: most take their usual size.")} </Accordion.Panel>
  </Accordion.Item>
  <Accordion.Item name="faq"> ... </Accordion.Item>
</Accordion.Root>`}
      >
        <Ui.Accordion.Root dataId="faq">
          {questions
          ->Array.mapWithIndex(((question, answer), index) =>
            <Ui.Accordion.Item key=question name="faq" defaultOpen={index == 0}>
              <Ui.Accordion.Trigger> {text(question)} </Ui.Accordion.Trigger>
              <Ui.Accordion.Panel> {text(answer)} </Ui.Accordion.Panel>
            </Ui.Accordion.Item>
          )
          ->Jsx.array}
        </Ui.Accordion.Root>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section name="Collapsible" summary="One section that opens and closes.">
      <Specimen.Example
        caption="Closed at first"
        code={`<Collapsible.Root>
  <Collapsible.Trigger> {text("Shipping and returns")} </Collapsible.Trigger>
  <Collapsible.Panel> {text("Free over $50.")} </Collapsible.Panel>
</Collapsible.Root>`}
      >
        <Ui.Collapsible.Root>
          <Ui.Collapsible.Trigger> {text("Shipping and returns")} </Ui.Collapsible.Trigger>
          <Ui.Collapsible.Panel>
            {text("Free over $50. Returns within 30 days, at no cost.")}
          </Ui.Collapsible.Panel>
        </Ui.Collapsible.Root>
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
