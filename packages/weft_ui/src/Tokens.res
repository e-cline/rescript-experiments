/***
The theme: CSS variables every component's styles use, named for what they're for (`surface`,
`fgMuted`), not what they look like, so another theme (a dark one, a brand's) is only other values.

An app sets the ones it wants on `:root`, in a style file with a class its outermost element wears
(a page is sent a sheet with the classes it has), so `<body>` sees them too:

```rescript
Css.global(~selector=":root", {vars: [(WeftUi.Tokens.accent, "#9a4b22")]})
let root = Css.class({display: Block}) // on the page's outermost element
```

The defaults are declared on `:where(:root)`, so a value set anywhere else wins, whichever
stylesheet loads first. They're a neutral look: greys, and a blue accent. Each text colour has at
least 4.5:1 contrast on `bg` and `surface`, and each `*SoftFg` on its `*Soft`; `borderStrong`
(inputs' borders) has 3:1.
*/
open WeftCss

/**
The cascade layer every weft_ui class is in: `weft.components.ui`, a sublayer of `weft_css`'s
`weft.components`, whose own rules (an app's classes) win over it whichever loads first.
*/
let layer = "weft.components.ui"

/** A variable's value, `var(--...)`, for properties written as strings (`border`, `boxShadow`). */
let value = var => `var(${Css.varName(var)})`

// Surfaces and text
let bg = Css.var("#ffffff")
let surface = Css.var("#ffffff")
/** A recessed surface: a table's header, a hovered row, a skeleton. */
let surfaceMuted = Css.var("#f4f4f5")
let fg = Css.var("#18181b")
let fgMuted = Css.var("#52525b")
let border = Css.var("#e4e4e7")
/** Form controls' borders, which need 3:1 contrast. */
let borderStrong = Css.var("#71717a")

// The accent, and the tones (each a solid colour, the text on it, and a soft background with its text)
let accent = Css.var("#2563eb")
let accentHover = Css.var("#1d4ed8")
let accentFg = Css.var("#ffffff")
let accentSoft = Css.var("#eff6ff")
let accentSoftFg = Css.var("#1e40af")

let danger = Css.var("#dc2626")
let dangerHover = Css.var("#b91c1c")
let dangerFg = Css.var("#ffffff")
let dangerSoft = Css.var("#fef2f2")
let dangerSoftFg = Css.var("#991b1b")

let success = Css.var("#15803d")
let successFg = Css.var("#ffffff")
let successSoft = Css.var("#f0fdf4")
let successSoftFg = Css.var("#166534")

let warning = Css.var("#b45309")
let warningFg = Css.var("#ffffff")
let warningSoft = Css.var("#fffbeb")
let warningSoftFg = Css.var("#92400e")

let neutralSoft = Css.var("#f4f4f5")
let neutralSoftFg = Css.var("#3f3f46")

/** The focus ring's colour (`:focus-visible`). */
let focusRing = Css.var("#2563eb")

// Shape
let radiusSm = Css.var("4px")
let radiusMd = Css.var("6px")
let radiusLg = Css.var("10px")
let radiusFull = Css.var("9999px")

// Space: the gaps and paddings components use, smallest to largest
let spaceXs = Css.var("4px")
let spaceSm = Css.var("8px")
let spaceMd = Css.var("12px")
let spaceLg = Css.var("16px")
let spaceXl = Css.var("24px")
let spaceXxl = Css.var("32px")

// Text sizes
let textXs = Css.var("0.75rem")
let textSm = Css.var("0.875rem")
let textMd = Css.var("1rem")
let textLg = Css.var("1.125rem")
let textXl = Css.var("1.25rem")
let textXxl = Css.var("1.5rem")
let textXxxl = Css.var("1.875rem")

// Controls' heights (buttons, inputs): `lg` is a comfortable touch target
let controlSm = Css.var("28px")
let controlMd = Css.var("36px")
let controlLg = Css.var("44px")

// Containers' widths
let containerSm = Css.var("560px")
let containerMd = Css.var("720px")
let containerLg = Css.var("1100px")
let containerXl = Css.var("1280px")

// Elevation
let shadowSm = Css.var("0 1px 2px rgb(0 0 0 / 0.06)")
let shadowMd = Css.var("0 4px 16px rgb(0 0 0 / 0.12)")
let shadowLg = Css.var("0 12px 40px rgb(0 0 0 / 0.2)")

// Motion: durations, which are zero for anyone who asked for reduced motion
let durationFast = Css.var("120ms")
let durationMedium = Css.var("200ms")
/** A spinner's turn: slower, not stopped, with reduced motion, so it still says "working". */
let durationSpin = Css.var("0.8s")

Css.global(
  ~selector=":where(:root)",
  {
    media: [
      Css.media(
        ~query="(prefers-reduced-motion: reduce)",
        {
          vars: [(durationFast, "0s"), (durationMedium, "0s"), (durationSpin, "2.4s")],
        },
      ),
    ],
  },
)

/** The focus ring, as every focusable component draws it. */
let focusVisible = () => Css.style({outline: `2px solid ${value(focusRing)}`, outlineOffset: Px(2)})
