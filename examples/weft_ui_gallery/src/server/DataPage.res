@@weft.server

module Ui = WeftUi

let text = WeftDom.Jsx.string

let orders = [
  ("A-1042", "Oct 2", "Delivered", 4800),
  ("A-1057", "Oct 9", "Shipped", 12950),
  ("A-1063", "Oct 21", "Placed", 2200),
]

let money = cents => `$${Float.toFixed(Int.toFloat(cents) /. 100., ~digits=2)}`

let statusTone = (status): Ui.Variants.tone =>
  switch status {
  | "Delivered" => #success
  | "Shipped" => #accent
  | _ => #neutral
  }

@weft.component({kind: Server})
let make = (~group: Groups.group) =>
  <Specimen.Page title=group.title summary=group.summary>
    <Specimen.Section
      name="Table" summary="Data in rows and columns, read cell by cell with its row and column."
    >
      <Specimen.Example caption="A captioned table in a scrolling region, numbers at the end">
        <Ui.Table.Root scrollLabel="Orders">
          <Ui.Table.Caption> {text("Your orders")} </Ui.Table.Caption>
          <Ui.Table.Head>
            <Ui.Table.Row>
              <Ui.Table.HeaderCell> {text("Order")} </Ui.Table.HeaderCell>
              <Ui.Table.HeaderCell> {text("Placed")} </Ui.Table.HeaderCell>
              <Ui.Table.HeaderCell> {text("Status")} </Ui.Table.HeaderCell>
              <Ui.Table.HeaderCell numeric=true> {text("Total")} </Ui.Table.HeaderCell>
            </Ui.Table.Row>
          </Ui.Table.Head>
          <Ui.Table.Body>
            {orders
            ->Array.map(((id, placed, status, total)) =>
              <Ui.Table.Row key=id>
                <Ui.Table.HeaderCell scope=#row> {text(id)} </Ui.Table.HeaderCell>
                <Ui.Table.Cell> {text(placed)} </Ui.Table.Cell>
                <Ui.Table.Cell>
                  <Ui.Badge tone={statusTone(status)}> {text(status)} </Ui.Badge>
                </Ui.Table.Cell>
                <Ui.Table.Cell numeric=true> {text(money(total))} </Ui.Table.Cell>
              </Ui.Table.Row>
            )
            ->WeftDom.Jsx.array}
          </Ui.Table.Body>
          <Ui.Table.Foot>
            <Ui.Table.Row>
              <Ui.Table.HeaderCell scope=#row colSpan=3> {text("Total")} </Ui.Table.HeaderCell>
              <Ui.Table.Cell numeric=true> {text(money(19950))} </Ui.Table.Cell>
            </Ui.Table.Row>
          </Ui.Table.Foot>
        </Ui.Table.Root>
      </Specimen.Example>
      <Specimen.Example caption="density=#compact, striped=true, a row selected">
        <Ui.Table.Root density=#compact striped=true ariaLabel="Sizes">
          <Ui.Table.Head>
            <Ui.Table.Row>
              <Ui.Table.HeaderCell> {text("Size")} </Ui.Table.HeaderCell>
              <Ui.Table.HeaderCell numeric=true> {text("Chest (cm)")} </Ui.Table.HeaderCell>
            </Ui.Table.Row>
          </Ui.Table.Head>
          <Ui.Table.Body>
            {[("S", "88–96"), ("M", "96–104"), ("L", "104–112"), ("XL", "112–124")]
            ->Array.map(((size, chest)) =>
              <Ui.Table.Row key=size selected={size == "M"}>
                <Ui.Table.HeaderCell scope=#row> {text(size)} </Ui.Table.HeaderCell>
                <Ui.Table.Cell numeric=true> {text(chest)} </Ui.Table.Cell>
              </Ui.Table.Row>
            )
            ->WeftDom.Jsx.array}
          </Ui.Table.Body>
        </Ui.Table.Root>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section
      name="List" summary="Items one under the other: divided, a gap apart, or with markers."
    >
      <Ui.Grid minItemWidth="220px" gap=#lg>
        <Specimen.Example caption="divided=true">
          <Ui.List.Root divided=true>
            <Ui.List.Item> {text("Shopping list")} </Ui.List.Item>
            <Ui.List.Item> {text("Ideas for the weekend")} </Ui.List.Item>
            <Ui.List.Item> {text("Books to read")} </Ui.List.Item>
          </Ui.List.Root>
        </Specimen.Example>
        <Specimen.Example caption="markers=true, as_=#ol">
          <Ui.List.Root as_=#ol markers=true gap=#xs>
            <Ui.List.Item> {text("Preheat the oven")} </Ui.List.Item>
            <Ui.List.Item> {text("Mix the dough")} </Ui.List.Item>
            <Ui.List.Item> {text("Bake for 20 minutes")} </Ui.List.Item>
          </Ui.List.Root>
        </Specimen.Example>
      </Ui.Grid>
    </Specimen.Section>
    <Specimen.Section
      name="DescriptionList" summary="Terms and their details, side by side or stacked."
    >
      <Ui.Grid minItemWidth="220px" gap=#lg>
        <Specimen.Example caption="A summary, details at the end">
          <Ui.DescriptionList.Root detailsAlign=#end>
            <Ui.DescriptionList.Term> {text("Subtotal")} </Ui.DescriptionList.Term>
            <Ui.DescriptionList.Details> {text("$199.50")} </Ui.DescriptionList.Details>
            <Ui.DescriptionList.Term> {text("Discount")} </Ui.DescriptionList.Term>
            <Ui.DescriptionList.Details> {text("−$20.00")} </Ui.DescriptionList.Details>
            <Ui.DescriptionList.Term> {text("Total")} </Ui.DescriptionList.Term>
            <Ui.DescriptionList.Details> {text("$179.50")} </Ui.DescriptionList.Details>
          </Ui.DescriptionList.Root>
        </Specimen.Example>
        <Specimen.Example caption="layout=#stacked">
          <Ui.DescriptionList.Root layout=#stacked>
            <Ui.DescriptionList.Term> {text("Material")} </Ui.DescriptionList.Term>
            <Ui.DescriptionList.Details> {text("Merino wool")} </Ui.DescriptionList.Details>
            <Ui.DescriptionList.Term> {text("Care")} </Ui.DescriptionList.Term>
            <Ui.DescriptionList.Details> {text("Hand wash, dry flat")} </Ui.DescriptionList.Details>
          </Ui.DescriptionList.Root>
        </Specimen.Example>
      </Ui.Grid>
    </Specimen.Section>
    <Specimen.Section name="Breadcrumbs" summary="The trail of pages above this one.">
      <Specimen.Example caption="Two links, then the page">
        <Ui.Breadcrumbs.Root>
          <Ui.Breadcrumbs.Item>
            <a href="#breadcrumbs"> {text("Home")} </a>
          </Ui.Breadcrumbs.Item>
          <Ui.Breadcrumbs.Item>
            <a href="#breadcrumbs"> {text("Scarves")} </a>
          </Ui.Breadcrumbs.Item>
          <Ui.Breadcrumbs.Current> {text("Wool scarf")} </Ui.Breadcrumbs.Current>
        </Ui.Breadcrumbs.Root>
      </Specimen.Example>
    </Specimen.Section>
    <Specimen.Section name="Steps" summary="Progress through steps: done, current, still to come.">
      <Specimen.Example caption="Horizontal">
        <Ui.Steps.Root ariaLabel="Checkout">
          <Ui.Steps.Step status=#complete> {text("Address")} </Ui.Steps.Step>
          <Ui.Steps.Step status=#current> {text("Delivery")} </Ui.Steps.Step>
          <Ui.Steps.Step status=#upcoming> {text("Review")} </Ui.Steps.Step>
        </Ui.Steps.Root>
      </Specimen.Example>
      <Specimen.Example caption="orientation=#vertical">
        <Ui.Steps.Root ariaLabel="Delivery" orientation=#vertical>
          <Ui.Steps.Step status=#complete> {text("Placed")} </Ui.Steps.Step>
          <Ui.Steps.Step status=#complete> {text("Packed")} </Ui.Steps.Step>
          <Ui.Steps.Step status=#current> {text("Shipped")} </Ui.Steps.Step>
          <Ui.Steps.Step status=#upcoming> {text("Delivered")} </Ui.Steps.Step>
        </Ui.Steps.Root>
      </Specimen.Example>
    </Specimen.Section>
  </Specimen.Page>
