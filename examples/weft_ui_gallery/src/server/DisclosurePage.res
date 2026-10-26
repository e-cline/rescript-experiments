@@weft.server

module Ui = WeftUi

let text = WeftDom.Jsx.string

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
      >
        <DisclosureDemos.Settings />
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="Accordion"
      summary="Sections that open and close, divided: the browser's details, so they work before (or without) JavaScript."
    >
      <Specimen.Example caption="One open at a time (the items share a name), the first open">
        <Ui.Accordion.Root dataId="faq">
          {questions
          ->Array.mapWithIndex(((question, answer), index) =>
            <Ui.Accordion.Item key=question name="faq" defaultOpen={index == 0}>
              <Ui.Accordion.Trigger> {text(question)} </Ui.Accordion.Trigger>
              <Ui.Accordion.Panel> {text(answer)} </Ui.Accordion.Panel>
            </Ui.Accordion.Item>
          )
          ->WeftDom.Jsx.array}
        </Ui.Accordion.Root>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section name="Collapsible" summary="One section that opens and closes.">
      <Specimen.Example caption="Closed at first">
        <Ui.Collapsible.Root>
          <Ui.Collapsible.Trigger> {text("Shipping and returns")} </Ui.Collapsible.Trigger>
          <Ui.Collapsible.Panel>
            {text("Free over $50. Returns within 30 days, at no cost.")}
          </Ui.Collapsible.Panel>
        </Ui.Collapsible.Root>
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
