/***
The notes' look: weft_ui's components, in the notes' colours. `root`, on the page's outermost
element, sets weft_ui's tokens to them (and so brings this sheet to every page); the page's font and
background are the only rules for elements. The components' own styles are beside them.
*/
open WeftCss

module Tokens = WeftUi.Tokens

/** The notes' palette, as weft_ui's tokens. */
let root = Css.class({
  vars: [
    (Tokens.fg, "#22201d"),
    (Tokens.fgMuted, "#6f6a63"),
    (Tokens.border, "#e4e0d9"),
    (Tokens.borderStrong, "#8a847b"),
    (Tokens.bg, "#fcfbf8"),
    (Tokens.surface, "#ffffff"),
    (Tokens.surfaceMuted, "#f3f1ec"),
    (Tokens.accent, "#2f5d8a"),
    (Tokens.accentHover, "#254a6e"),
    (Tokens.accentSoft, "#eef3f8"),
    (Tokens.accentSoftFg, "#244867"),
    (Tokens.focusRing, "#2f5d8a"),
    (Tokens.danger, "#a12a2a"),
    (Tokens.dangerSoft, "#fbf1f0"),
    (Tokens.dangerSoftFg, "#8a2323"),
  ],
})

Css.global(~selector="*", {boxSizing: BorderBox})

Css.global(
  ~selector="body",
  {
    margin: Zero,
    font: "16px/1.6 system-ui, sans-serif",
    color: Raw("#22201d"),
    backgroundColor: Raw("#fcfbf8"),
  },
)

/** A one-pixel border in the line colour, for the page's own rules. */
let hairline = () => `1px solid ${Tokens.value(Tokens.border)}`
