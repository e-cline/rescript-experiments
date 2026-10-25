/***
The gallery's own look, which is weft_ui's defaults: the page's font and colours from its tokens,
and `root`, on the outermost element, where a theme would set the tokens.
*/
open WeftCss

module Tokens = WeftUi.Tokens

Css.global(~selector="*", {boxSizing: BorderBox})

Css.global(
  ~selector="body",
  {
    margin: Zero,
    font: "15px/1.5 system-ui, -apple-system, 'Segoe UI', sans-serif",
    color: Var(Tokens.fg),
    backgroundColor: Var(Tokens.bg),
  },
)

/** The outermost element: where the tokens' values for a theme go. */
let root = Css.class({minHeight: Vh(100.)})
