/***
Where a page is: the trail of pages above it, as links, then the page itself.

```rescript
<Breadcrumbs.Root>
  <Breadcrumbs.Item> <AppLink href="/"> {text("Home")} </AppLink> </Breadcrumbs.Item>
  <Breadcrumbs.Item> <AppLink href="/c/scarves"> {text("Scarves")} </AppLink> </Breadcrumbs.Item>
  <Breadcrumbs.Current> {text("Wool scarf")} </Breadcrumbs.Current>
</Breadcrumbs.Root>
```

A `nav` named "Breadcrumbs" (or `label`), with an ordered list in it. The separators between items
are drawn by CSS, and not read out.

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let list = Css.class(
    ~layer,
    {
      display: Flex,
      flexWrap: Wrap,
      alignItems: Center,
      gap: Var(Tokens.spaceXs),
      margin: Zero,
      padding: Zero,
      listStyle: None,
      fontSize: Var(Tokens.textSm),
      color: Var(Tokens.fgMuted),
    },
  )
  let item = Css.class(
    ~layer,
    {
      display: InlineFlex,
      alignItems: Center,
      gap: Var(Tokens.spaceXs),
      selectors: [
        // The separator: "/", with no text for assistive technology.
        (
          "& + &::before",
          Css.style({
            content: "\"/\" / \"\"",
            color: Var(Tokens.border),
            paddingInlineEnd: Var(Tokens.spaceXs),
          }),
        ),
        ("a", Css.style({color: Raw("inherit"), textDecoration: None})),
        ("a:hover", Css.style({color: Var(Tokens.fg), textDecoration: Underline})),
        ("a:focus-visible", Tokens.focusVisible()),
      ],
    },
  )
  let current = Css.class(~layer, {color: Var(Tokens.fg), fontWeight: 500})
}

module Root = {
  @weft.component
  let make = (~label="Breadcrumbs", ~id=?, ~className=?, ~style=?, ~dataId=?, ~children=?) =>
    <nav ?id ariaLabel=label ?style ?dataId className=?className>
      <ol className=Styles.list ?children />
    </nav>
}

module Item = {
  @weft.component
  let make = (~className=?, ~dataId=?, ~children=?) =>
    <li className={Host.classes([Styles.item], className)} ?dataId ?children />
}

module Current = {
  /** The page itself, the trail's end (`aria-current="page"`). */
  @weft.component
  let make = (~className=?, ~dataId=?, ~children=?) =>
    <li className=Styles.item ?dataId>
      <span className={Host.classes([Styles.current], className)} ariaCurrent="page" ?children />
    </li>
}
