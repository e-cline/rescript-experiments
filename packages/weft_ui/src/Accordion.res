/***
Sections that open and close, one under another, divided: questions and answers, a product's
details. Each item is a `Collapsible` (the browser's `<details>`), so it works with no JavaScript.
Give the items one `name` for only one to be open at a time (the browser's exclusive accordion).

```rescript
<Accordion.Root>
  <Accordion.Item name="faq">
    <Accordion.Trigger> {text("Is it true to size?")} </Accordion.Trigger>
    <Accordion.Panel> {text("Yes: most take their usual size.")} </Accordion.Panel>
  </Accordion.Item>
  ...
</Accordion.Root>
```

Static: a server component can render it. (So the `name` is each item's: a static component can't
hand it down through a context.)
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let root = Css.class(
    ~layer,
    {
      display: Flex,
      flexDirection: Column,
      borderTop: `1px solid ${Tokens.value(Tokens.border)}`,
    },
  )
  let item = Css.class(
    ~layer,
    {
      borderBottom: `1px solid ${Tokens.value(Tokens.border)}`,
      selectors: [("& > summary", Css.style({paddingBlock: Var(Tokens.spaceMd)}))],
    },
  )
}

module Root = {
  @weft.component
  let make = (~id=?, ~className=?, ~style=?, ~dataId=?, ~ariaLabel=?, ~children=?) =>
    <div
      ?id className={Host.classes([Styles.root], className)} ?style ?dataId ?ariaLabel ?children
    />
}

module Item = {
  /** A section: `name`, shared by the accordion's items, keeps only one of them open. */
  @weft.component
  let make = (~name=?, ~defaultOpen=false, ~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <Collapsible.Root
      ?name defaultOpen ?id className={Host.classes([Styles.item], className)} ?dataId ?children
    />
}

module Trigger = Collapsible.Trigger
module Panel = Collapsible.Panel
