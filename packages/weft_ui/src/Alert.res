/***
A message in a box: something went wrong, worked, or is worth knowing. `tone` picks its colours
(and its role, unless `role` does: an `alert`, announced at once, for `#danger` and `#warning`; a
`status` otherwise; `#none` for neither, a message there since the page loaded).

```rescript
<Alert.Root tone=#danger>
  <Alert.Title> {text("Couldn't load this")} </Alert.Title>
  <Alert.Description> {text(message)} </Alert.Description>
  <Alert.Action> <Button onClick=retry> {text("Retry")} </Button> </Alert.Action>
</Alert.Root>
```

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let root = Css.class(
    ~layer,
    {
      display: Grid,
      gridTemplateColumns: "minmax(0, 1fr) auto",
      columnGap: Var(Tokens.spaceMd),
      rowGap: Var(Tokens.spaceXs),
      alignItems: Center,
      padding: Pair(Var(Tokens.spaceMd), Var(Tokens.spaceLg)),
      borderRadius: Var(Tokens.radiusMd),
      border: "1px solid",
      borderInlineStart: "4px solid",
      fontSize: Var(Tokens.textSm),
    },
  )
  let neutral = Css.class(
    ~layer,
    {
      color: Var(Tokens.neutralSoftFg),
      backgroundColor: Var(Tokens.neutralSoft),
      borderColor: Var(Tokens.border),
    },
  )
  let info = Css.class(
    ~layer,
    {
      color: Var(Tokens.accentSoftFg),
      backgroundColor: Var(Tokens.accentSoft),
      borderColor: Var(Tokens.accent),
    },
  )
  let success = Css.class(
    ~layer,
    {
      color: Var(Tokens.successSoftFg),
      backgroundColor: Var(Tokens.successSoft),
      borderColor: Var(Tokens.success),
    },
  )
  let warning = Css.class(
    ~layer,
    {
      color: Var(Tokens.warningSoftFg),
      backgroundColor: Var(Tokens.warningSoft),
      borderColor: Var(Tokens.warning),
    },
  )
  let danger = Css.class(
    ~layer,
    {
      color: Var(Tokens.dangerSoftFg),
      backgroundColor: Var(Tokens.dangerSoft),
      borderColor: Var(Tokens.danger),
    },
  )
  let title = Css.class(~layer, {gridColumn: "1", margin: Zero, fontWeight: 600})
  let description = Css.class(~layer, {gridColumn: "1", margin: Zero})
  let action = Css.class(
    ~layer,
    {
      gridColumn: "2",
      gridRow: "1 / span 2",
      display: Flex,
      gap: Var(Tokens.spaceSm),
      media: [Css.media(~query="(max-width: 480px)", {gridColumn: "1", gridRow: "auto"})],
    },
  )
}

type tone = [#neutral | #info | #success | #warning | #danger]

module Root = {
  @weft.component
  let make = (
    ~tone: tone=#info,
    ~role: option<[#alert | #status | #none]>=?,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~attrs: WeftDom.DomProps.props={},
    ~children=?,
  ) => {
    let role = switch (role, tone) {
    | (Some(#none), _) => None
    | (Some(role), _) => Some((role :> string))
    | (None, #danger | #warning) => Some("alert")
    | (None, _) => Some("status")
    }
    <div
      {...attrs}
      ?id
      className={Host.classes(
        [
          Styles.root,
          switch tone {
          | #neutral => Styles.neutral
          | #info => Styles.info
          | #success => Styles.success
          | #warning => Styles.warning
          | #danger => Styles.danger
          },
        ],
        className,
      )}
      ?style
      ?dataId
      ?role
      dataVariant={(tone :> string)}
      ?children
    />
  }
}

module Title = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <p ?id className={Host.classes([Styles.title], className)} ?dataId ?children />
}

module Description = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <div ?id className={Host.classes([Styles.description], className)} ?dataId ?children />
}

module Action = {
  @weft.component
  let make = (~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <div ?id className={Host.classes([Styles.action], className)} ?dataId ?children />
}
