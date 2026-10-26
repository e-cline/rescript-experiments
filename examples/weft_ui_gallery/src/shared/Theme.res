/***
The gallery's own look: weft_ui's defaults, the page's font and colours from its tokens, and the
themes the header's switcher picks between (each demo app's palette), each a class on the outermost
element setting the tokens there. They're all in this file, whose `root` every page renders, so
every page is sent them, whichever is picked.
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

/** The outermost element: where a theme's tokens go, and the page's colours from them. */
let root = Css.class({
  minHeight: Vh(100.),
  color: Var(Tokens.fg),
  backgroundColor: Var(Tokens.bg),
})

/** weft_notes' palette. */
let notes = Css.class({
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

/** weft_shop's palette. */
let shop = Css.class({
  vars: [
    (Tokens.fg, "#1d1b19"),
    (Tokens.fgMuted, "#6b645c"),
    (Tokens.border, "#e6e0d8"),
    (Tokens.borderStrong, "#8c847a"),
    (Tokens.bg, "#fbf8f4"),
    (Tokens.surface, "#ffffff"),
    (Tokens.surfaceMuted, "#f3eee7"),
    (Tokens.accent, "#9a4b22"),
    (Tokens.accentHover, "#7f3d1b"),
    (Tokens.accentSoft, "#f8ece4"),
    (Tokens.accentSoftFg, "#7a3a18"),
    (Tokens.focusRing, "#9a4b22"),
    (Tokens.danger, "#b3261e"),
    (Tokens.dangerHover, "#951f19"),
    (Tokens.dangerSoft, "#fdf1f0"),
    (Tokens.dangerSoftFg, "#8f1e18"),
    (Tokens.success, "#2f6b3a"),
    (Tokens.successSoft, "#eef6ef"),
    (Tokens.successSoftFg, "#285c32"),
    (Tokens.radiusLg, "10px"),
  ],
})

/** The themes, by name, with what the switcher calls them. */
let themes = [("default", "weft_ui"), ("notes", "Notes"), ("shop", "Shop")]

/** The cookie that keeps the theme picked, for the server to render it. */
let cookieName = "gallery-theme"

/** A theme by name, the default for one it doesn't know. */
let parse = name => themes->Array.some(((known, _)) => known == name) ? name : "default"

/** The outermost element's classes, in a theme. */
let rootClass = theme =>
  Css.cx([
    root,
    switch theme {
    | "notes" => notes
    | "shop" => shop
    | _ => ""
    },
  ])
