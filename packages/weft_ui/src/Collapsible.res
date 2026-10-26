/***
A section that opens and closes: the browser's `<details>` and `<summary>`, so it works with no
JavaScript (on a server component's page before hydrating, or with none), with the keyboard, and
with find-in-page, which opens it to show a match.

```rescript
<Collapsible.Root>
  <Collapsible.Trigger> {text("Shipping and returns")} </Collapsible.Trigger>
  <Collapsible.Panel> ... </Collapsible.Panel>
</Collapsible.Root>
```

`defaultOpen` opens it at first; after that it's the person's. (Controlling it is for later.)

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let root = Css.class(~layer, {minWidth: Zero})
  let trigger = Css.class(
    ~layer,
    {
      display: Flex,
      alignItems: Center,
      justifyContent: SpaceBetween,
      gap: Var(Tokens.spaceSm),
      paddingBlock: Var(Tokens.spaceSm),
      fontWeight: 500,
      color: Var(Tokens.fg),
      cursor: Pointer,
      listStyle: None,
      borderRadius: Var(Tokens.radiusSm),
      focusVisible: Tokens.focusVisible(),
      // The browser's own marker goes; a chevron of its own, turned when it's open.
      selectors: [
        ("&::-webkit-details-marker", Css.style({display: None})),
        (
          "&::after",
          Css.style({
            content: "\"\"",
            flexShrink: 0.,
            width: Px(7),
            height: Px(7),
            marginInlineEnd: Px(4),
            borderRight: "1.5px solid",
            borderBottom: "1.5px solid",
            borderColor: Var(Tokens.fgMuted),
            transform: "rotate(45deg)",
            transition: `transform ${Tokens.value(Tokens.durationFast)}`,
          }),
        ),
        ("details[open] > &::after", Css.style({transform: "rotate(-135deg)"})),
      ],
    },
  )
  let panel = Css.class(
    ~layer,
    {paddingBlockEnd: Var(Tokens.spaceMd), color: Var(Tokens.fg), fontSize: Var(Tokens.textSm)},
  )
}

module Root = {
  @weft.component
  let make = (
    ~defaultOpen=false,
    ~name=?,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~onToggle=?,
    ~children=?,
  ) =>
    <details
      ?id
      open_=defaultOpen
      ?name
      className={Host.classes([Styles.root], className)}
      ?style
      ?dataId
      ?onToggle
      ?children
    />
}

module Trigger = {
  /** What it's about, which opens and closes it: a `<summary>`. */
  @weft.component
  let make = (~className=?, ~dataId=?, ~children=?) =>
    <summary className={Host.classes([Styles.trigger], className)} ?dataId ?children />
}

module Panel = {
  @weft.component
  let make = (~className=?, ~dataId=?, ~children=?) =>
    <div className={Host.classes([Styles.panel], className)} ?dataId ?children />
}
