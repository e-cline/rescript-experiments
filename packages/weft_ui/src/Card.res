/***
A card: a surface for one thing (a product, a summary), with optional parts in it.

```rescript
<Card.Root as_=#article>
  <Card.Header>
    <Card.Title> {text("Wool scarf")} </Card.Title>
    <Card.Description> {text("Merino, hand-dyed")} </Card.Description>
  </Card.Header>
  <Card.Content> ... </Card.Content>
  <Card.Footer> ... </Card.Footer>
</Card.Root>
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
      gap: Var(Tokens.spaceMd),
      minWidth: Zero,
      color: Var(Tokens.fg),
      backgroundColor: Var(Tokens.surface),
      borderRadius: Var(Tokens.radiusLg),
    },
  )
  let outline = Css.class(~layer, {border: `1px solid ${Tokens.value(Tokens.border)}`})
  let elevated = Css.class(
    ~layer,
    {border: `1px solid ${Tokens.value(Tokens.border)}`, boxShadow: Tokens.value(Tokens.shadowSm)},
  )
  let ghost = Css.class(~layer, {backgroundColor: Transparent})
  let paddingNone = Css.class(~layer, {padding: Zero})
  let paddingSm = Css.class(~layer, {padding: Var(Tokens.spaceSm)})
  let paddingMd = Css.class(~layer, {padding: Var(Tokens.spaceLg)})
  let paddingLg = Css.class(~layer, {padding: Var(Tokens.spaceXl)})
  /** A card that's a link or a button as a whole: its border shows it, on hover and focus. */
  let interactive = Css.class(
    ~layer,
    {
      transition: `border-color ${Tokens.value(Tokens.durationFast)}`,
      hover: Css.style({borderColor: Var(Tokens.borderStrong)}),
      focusWithin: Css.style({borderColor: Var(Tokens.borderStrong)}),
    },
  )
  let header = Css.class(~layer, {display: Flex, flexDirection: Column, gap: Var(Tokens.spaceXs)})
  let title = Css.class(~layer, {margin: Zero, fontSize: Var(Tokens.textLg), fontWeight: 600})
  let description = Css.class(
    ~layer,
    {margin: Zero, color: Var(Tokens.fgMuted), fontSize: Var(Tokens.textSm)},
  )
  let content = Css.class(~layer, {minWidth: Zero})
  let footer = Css.class(
    ~layer,
    {display: Flex, alignItems: Center, gap: Var(Tokens.spaceSm), flexWrap: Wrap},
  )
}

module Root = {
  @weft.component
  let make = (
    ~as_: [#div | #article | #section | #li | #aside]=#div,
    ~variant: [#outline | #elevated | #ghost]=#outline,
    ~padding: [#none | #sm | #md | #lg]=#md,
    ~interactive=false,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~ariaLabel=?,
    ~ariaLabelledby=?,
    ~attrs: WeftDom.DomProps.props={},
    ~children=?,
  ) =>
    Host.element(
      (as_ :> string),
      {
        ...attrs,
        ?id,
        className: Host.classes(
          Array.concat(
            [
              Styles.root,
              switch variant {
              | #outline => Styles.outline
              | #elevated => Styles.elevated
              | #ghost => Styles.ghost
              },
              switch padding {
              | #none => Styles.paddingNone
              | #sm => Styles.paddingSm
              | #md => Styles.paddingMd
              | #lg => Styles.paddingLg
              },
            ],
            interactive ? [Styles.interactive] : [],
          ),
          className,
        ),
        ?style,
        ?dataId,
        ?ariaLabel,
        ?ariaLabelledby,
        dataVariant: (variant :> string),
        ?children,
      },
    )
}

module Header = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <div ?id className={Host.classes([Styles.header], className)} ?dataId ?children />
}

module Title = {
  /** The card's heading: an `<h3>` unless `level` says otherwise. */
  @weft.component
  let make = (~level: Variants.level=#h3, ~id=?, ~className=?, ~dataId=?, ~children=?) =>
    Host.element(
      Variants.levelTag(level),
      {?id, className: Host.classes([Styles.title], className), ?dataId, ?children},
    )
}

module Description = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <p ?id className={Host.classes([Styles.description], className)} ?dataId ?children />
}

module Content = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <div ?id className={Host.classes([Styles.content], className)} ?dataId ?children />
}

module Footer = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <div ?id className={Host.classes([Styles.footer], className)} ?dataId ?children />
}
