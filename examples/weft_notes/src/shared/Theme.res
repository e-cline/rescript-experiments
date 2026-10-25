/***
The notes' look (with `weft_css`): its colours, as CSS variables, the page's own rules, and the
looks server and client components share. Each component's own styles are beside it.
*/
open WeftCss

let ink = Css.var("#22201d")
let muted = Css.var("#6f6a63")
let line = Css.var("#e4e0d9")
let paper = Css.var("#fcfbf8")
let accent = Css.var("#2f5d8a")
let danger = Css.var("#a12a2a")

/** A variable's value, for properties written as strings (`border`, `outline`, ...). */
let value = var => `var(${Css.varName(var)})`

/** A one-pixel border in the line colour. */
let hairline = () => `1px solid ${value(line)}`

Css.global(~selector="*", {boxSizing: BorderBox})

Css.global(
  ~selector="body",
  {
    margin: Zero,
    font: "16px/1.6 system-ui, sans-serif",
    color: Var(ink),
    backgroundColor: Var(paper),
  },
)

Css.global(~selector="a", {color: Var(accent)})

Css.global(~selector="h1, h2", {lineHeight: 1.25, margin: Pair(Zero, Zero)})

Css.global(
  ~selector="button, input",
  {
    font: "inherit",
    border: hairline(),
    borderRadius: Px(6),
    padding: Pair(Px(6), Px(10)),
    backgroundColor: Named("white"),
    color: Raw("inherit"),
  },
)

Css.global(
  ~selector="button",
  {
    cursor: Pointer,
    hover: Css.style({borderColor: Var(accent)}),
  },
)

Css.global(
  ~selector="input",
  {focusVisible: Css.style({outline: `2px solid ${value(accent)}`, outlineOffset: Px(1)})},
)

/** Secondary text: a date, a hint. */
let secondary = Css.class({color: Var(muted), fontSize: Rem(0.875)})

/** Something still loading. */
let loading = Css.class({color: Var(muted), fontStyle: Italic})

/** What went wrong (a refused save, an RPC's error). */
let error = Css.class({color: Var(danger), margin: Zero, flexBasis: Pct(100.)})

/** A list with no bullets, its items one under the other, between hairlines. */
let list = Css.class({
  listStyle: None,
  padding: Zero,
  margin: Zero,
  selectors: [("li", Css.style({padding: Pair(Px(10), Zero), borderBottom: hairline()}))],
})
