/***
The store's look (with `weft_css`): its colours, as CSS variables, the page's own rules, and the
looks both server and client components use. Each component's own styles are beside it.
*/
open WeftCss

let ink = Css.var("#1d1b19")
let muted = Css.var("#6b645c")
let line = Css.var("#e6e0d8")
let paper = Css.var("#fbf8f4")
let accent = Css.var("#9a4b22")
let sale = Css.var("#b3261e")

/** A variable's value, for properties written as strings (`border`, `outline`, ...). */
let value = var => `var(${Css.varName(var)})`

/** A one-pixel border in the line colour. */
let hairline = () => `1px solid ${value(line)}`

Css.global(~selector="*", {boxSizing: BorderBox})

Css.global(
  ~selector="body",
  {
    margin: Zero,
    font: "15px/1.5 system-ui, sans-serif",
    color: Var(ink),
    backgroundColor: Var(paper),
  },
)

Css.global(~selector="a", {color: Raw("inherit")})

Css.global(~selector="button, select, input, textarea", {font: "inherit"})

Css.global(
  ~selector="button",
  {
    cursor: Pointer,
    border: hairline(),
    backgroundColor: Named("white"),
    borderRadius: Px(6),
    padding: Pair(Px(4), Px(10)),
    disabled: Css.style({opacity: 0.5, cursor: Default}),
  },
)

/** Read by screen readers, not shown. */
let visuallyHidden = Css.class({
  position: Absolute,
  width: Px(1),
  height: Px(1),
  overflow: Hidden,
  clip: "rect(0 0 0 0)",
})

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

/** Something still loading. */
let placeholder = Css.class({
  color: Var(muted),
  padding: Px(12),
  borderRadius: Px(8),
  background: "repeating-linear-gradient(90deg, #f1ece5, #f1ece5 10px, #f6f2ec 10px, #f6f2ec 20px)",
})

/** A call to action: a dark button-like link. */
let cta = Css.class({
  display: InlineBlock,
  marginTop: Px(8),
  padding: Pair(Px(8), Px(14)),
  borderRadius: Px(6),
  backgroundColor: Var(ink),
  color: Named("white"),
  textDecoration: None,
})

/** What's being fetched again: dimmed until it's in. */
let stale = Css.class({opacity: 0.6})

/** One of a list of options, on a line of its own. */
let choice = Css.class({display: Block})
