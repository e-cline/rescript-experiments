/***
The app's styles, extracted at build time by `weftCss()` (in `vite.config.ts`): the page's own
rules, and a class for each part of it.
*/
open WeftCss

Css.global(
  ~selector="body",
  {
    fontFamily: "system-ui, sans-serif",
    maxWidth: Rem(32.),
    margin: Pair(Rem(2.), Auto),
    padding: Pair(Zero, Rem(1.)),
  },
)

let newTodo = Css.class({
  width: Pct(100.),
  fontSize: Rem(1.1),
  padding: Rem(0.5),
  boxSizing: BorderBox,
})

let list = Css.class({listStyle: None, padding: Zero})

let item = Css.class({
  display: Flex,
  gap: Rem(0.5),
  alignItems: Center,
  padding: Pair(Rem(0.25), Zero),
  selectors: [("button", Css.style({marginLeft: Auto}))],
})

let done = Css.class({
  selectors: [("span", Css.style({textDecoration: LineThrough, opacity: 0.6}))],
})

let footer = Css.class({display: Flex, gap: Rem(1.), alignItems: Center})

let filters = Css.class({
  selectors: [("button[aria-pressed=\"true\"]", Css.style({fontWeight: 700}))],
})
