/***
Styles shared by a server file (`Notes`) and an entrypoint (`Likes`): a variable, a global and a
class. `DEFINITION_SENTINEL_THEME` is in a definition, which must reach neither bundle.
*/
open WeftCss

let ink = Css.var("#1d1b19")

Css.global(~selector="body", {margin: Zero, color: Var(ink)})

let badge = Css.class({
  display: InlineBlock,
  padding: Pair(Px(2), Px(6)),
  content: "\"DEFINITION_SENTINEL_THEME\"",
})
