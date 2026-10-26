/***
The store's look: weft_ui's components, in the store's colours, which this file sets as weft_ui's
tokens on `:root` (winning over weft_ui's defaults, whichever loads first). `root`, on the page's
outermost element, is what brings this sheet to every page. The page's font and colours are the
only rules for elements; the looks the store's own components share (a product's picture, a
placeholder, "stale") are here, and each component's own styles are beside it.
*/
open WeftCss

module Tokens = WeftUi.Tokens

Css.global(
  ~selector=":root",
  {
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
  },
)

/** The page's outermost element (which brings this sheet to every page). */
let root = Css.class({display: Block})

// The store's colours by their old names, for its own styles.
let ink = Tokens.fg
let muted = Tokens.fgMuted
let line = Tokens.border
let accent = Tokens.accent
let sale = Tokens.danger

/** A variable's value, for properties written as strings (`border`, `outline`, ...). */
let value = Tokens.value

/** A one-pixel border in the line colour. */
let hairline = () => `1px solid ${value(line)}`

Css.global(~selector="*", {boxSizing: BorderBox})

Css.global(
  ~selector="body",
  {
    margin: Zero,
    font: "15px/1.5 system-ui, sans-serif",
    color: Var(Tokens.fg),
    backgroundColor: Var(Tokens.bg),
  },
)

// The store's links are in the colour of what they're in, unless they're weft_ui's (`Link`, a
// recipe), whose classes say otherwise.
Css.global(~selector="a", {color: Raw("inherit")})

/** A picture's hue, and its gradient's angle: each picture sets its own (`pictureVars`). */
let hue = Css.var("30")
let angle = Css.var("135deg")

/** A picture's gradient, in its hue (`pictureVars`): for the classes of pictures and thumbnails. */
let gradient = () =>
  Css.style({
    background: `linear-gradient(${value(angle)}, hsl(${value(hue)} 45% 70%), hsl(calc(${value(
        hue,
      )} + 30) 35% 40%))`,
  })

/** A product's picture (a card's, the gallery's): its gradient, four by three. */
let picture = Css.class({...gradient(), aspectRatio: "4 / 3", borderRadius: Px(8)})

/** A picture's `style`: its product's hue, and the view's angle (the first's, by default). */
let pictureVars = (~hue as productHue, ~view=0) =>
  Css.vars([(hue, Int.toString(productHue)), (angle, `${Int.toString(135 + view * 40)}deg`)])

/** Something still loading: a placeholder that says what. */
let placeholder = Css.class({
  color: Var(muted),
  padding: Px(12),
  borderRadius: Px(8),
  background: "repeating-linear-gradient(90deg, #f1ece5, #f1ece5 10px, #f6f2ec 10px, #f6f2ec 20px)",
})

/** What's being fetched again: dimmed until it's in. */
let stale = Css.class({opacity: 0.6})
