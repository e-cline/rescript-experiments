/***
What a place shows when there's nothing in it yet (an empty cart, no results), and what to do
about it.

```rescript
<EmptyState.Root>
  <EmptyState.Title> {text("Your cart is empty")} </EmptyState.Title>
  <EmptyState.Description> {text("Find something you like.")} </EmptyState.Description>
  <EmptyState.Action> <AppLink href="/" className={Button.className()}> ... </AppLink> </EmptyState.Action>
</EmptyState.Root>
```

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let root = Css.class(
    ~layer,
    {
      display: Flex,
      flexDirection: Column,
      alignItems: Center,
      gap: Var(Tokens.spaceSm),
      padding: Pair(Var(Tokens.spaceXl), Var(Tokens.spaceLg)),
      textAlign: Center,
      color: Var(Tokens.fgMuted),
    },
  )
  let bordered = Css.class(
    ~layer,
    {border: `1px dashed ${Tokens.value(Tokens.border)}`, borderRadius: Var(Tokens.radiusLg)},
  )
  let title = Css.class(
    ~layer,
    {margin: Zero, color: Var(Tokens.fg), fontSize: Var(Tokens.textMd), fontWeight: 600},
  )
  let description = Css.class(
    ~layer,
    {margin: Zero, fontSize: Var(Tokens.textSm), maxWidth: Ch(48.)},
  )
  let action = Css.class(
    ~layer,
    {display: Flex, gap: Var(Tokens.spaceSm), marginTop: Var(Tokens.spaceSm)},
  )
}

module Root = {
  @weft.component
  let make = (
    ~bordered=false,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~attrs: WeftDom.DomProps.props={},
    ~children=?,
  ) =>
    Host.withAttrs(
      attrs,
      <div
        ?id
        className={Host.classes(
          bordered ? [Styles.root, Styles.bordered] : [Styles.root],
          className,
        )}
        ?style
        ?dataId
        ?children
      />,
    )
}

module Title = {
  /** A paragraph, unless `level` makes it a heading. */
  @weft.component
  let make = (~level: option<Variants.level>=?, ~id=?, ~className=?, ~dataId=?, ~children=?) =>
    Host.element(
      level->Option.mapOr("p", Variants.levelTag),
      {?id, className: Host.classes([Styles.title], className), ?dataId, ?children},
    )
}

module Description = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <p ?id className={Host.classes([Styles.description], className)} ?dataId ?children />
}

module Action = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <div ?id className={Host.classes([Styles.action], className)} ?dataId ?children />
}
