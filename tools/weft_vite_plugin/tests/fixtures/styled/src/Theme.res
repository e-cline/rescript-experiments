/*** Variables and a global, used by the other files' rules. */
open WeftCss

let ink = Css.var("#1d1b19")
let accent = Css.var("#9a4b22")

Css.global(~selector="body", {margin: Zero, color: Var(ink)})
