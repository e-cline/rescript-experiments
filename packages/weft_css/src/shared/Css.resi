/***
Styles, written in ReScript next to the components that use them:

```rescript
open WeftCss

module Styles = {
  let button = Css.class({
    display: InlineFlex,
    gap: Rem(0.5),
    padding: Pair(Px(6), Px(12)),
    color: Var(Theme.onAccent),
    backgroundColor: Var(Theme.accent),
    hover: Css.style({backgroundColor: Var(Theme.accentHover)}),
  })
}

<button className=Styles.button> ... </button>
```

`Css.class` gives a class name, a string. Its CSS is extracted at build time (by the Weft Vite
plugin), into a stylesheet of the file's own, which the page loads when something uses the class.

**Styles are static.** `class`, `global`, `var` and `keyframes` go in a `let` at a module's top level
(in any nesting of modules), and `ppx_weft` names each one there; anywhere else is a compile error.
For a value that changes at run time, use a CSS variable (`var`, set with `vars` in a `style` prop),
a data attribute and a `selectors` rule, or a class per variant. A file not compiled with `ppx_weft`
fails as soon as it's loaded: these functions throw when called directly.

**The CSS.** A `t` is a record of optional fields, one per property. A field's name is the property's
in camel case (`backgroundColor` is `background-color`), a keyword constructor is the keyword in
kebab case (`InlineFlex` is `inline-flex`, `SpaceBetween` is `space-between`), and every value type
has `Raw(string)` for what isn't typed. Properties with values too varied to type usefully
(`border`, `transition`, `gridTemplateColumns`, ...) are strings.

Nested blocks are fields too: pseudo-classes and pseudo-elements (`hover`, `focusVisible`,
`before`, ...), `selectors` for any other selector relative to the class (`&` is the class:
`("&[aria-pressed=\"true\"]", ...)`; without one, the selector is a descendant: `("li", ...)`), and
`media` for at-rules (`media`, `supports`, `container`). They nest in each other.

**Order.** Classes are in the cascade layer `weft.components`; globals and variables in `weft.base`,
before it. An app's own unlayered CSS overrides both. Within a layer, rules from different files have
no order to rely on: compose a class from fragments (`{...Base.button, color: ...}`) rather than
stacking two conflicting classes on one element.
*/

/** A CSS custom property, made by `var`: its name, `--<name>`. */
type var

/** An animation's name, made by `keyframes`. */
type keyframes

/** Lengths, and `Pair` and `Four` for shorthands that take several (`padding`, `gap`, ...). */
type rec length =
  | Px(int)
  | Rem(float)
  | Em(float)
  | Pct(float)
  | Vw(float)
  | Vh(float)
  | Ch(float)
  | Fr(float)
  | Zero
  | Auto
  | Calc(string)
  | Pair(length, length)
  | Four(length, length, length, length)
  | Var(var)
  | Raw(string)

type color =
  | Hex(string)
  | Rgb(int, int, int)
  | Rgba(int, int, int, float)
  | Named(string)
  | CurrentColor
  | Transparent
  | Var(var)
  | Raw(string)

/**
Keywords: each constructor is its keyword at run time (`InlineFlex` is `"inline-flex"`), and
`Raw` any other value (`Raw("var(--x)")`).
*/
@unboxed
type display =
  | @as("block") Block
  | @as("inline") Inline
  | @as("inline-block") InlineBlock
  | @as("flex") Flex
  | @as("inline-flex") InlineFlex
  | @as("grid") Grid
  | @as("inline-grid") InlineGrid
  | @as("contents") Contents
  | @as("none") None
  | Raw(string)

@unboxed
type position =
  | @as("static") Static
  | @as("relative") Relative
  | @as("absolute") Absolute
  | @as("fixed") Fixed
  | @as("sticky") Sticky
  | Raw(string)

/** `align-items`, `align-self`, `justify-items`, `justify-self`. */
@unboxed
type align =
  | @as("start") Start
  | @as("end") End
  | @as("flex-start") FlexStart
  | @as("flex-end") FlexEnd
  | @as("center") Center
  | @as("baseline") Baseline
  | @as("stretch") Stretch
  | @as("normal") Normal
  | Raw(string)

/** `justify-content`, `align-content`. */
@unboxed
type justify =
  | @as("start") Start
  | @as("end") End
  | @as("flex-start") FlexStart
  | @as("flex-end") FlexEnd
  | @as("center") Center
  | @as("space-between") SpaceBetween
  | @as("space-around") SpaceAround
  | @as("space-evenly") SpaceEvenly
  | @as("stretch") Stretch
  | @as("normal") Normal
  | Raw(string)

@unboxed
type flexDirection =
  | @as("row") Row
  | @as("row-reverse") RowReverse
  | @as("column") Column
  | @as("column-reverse") ColumnReverse
  | Raw(string)

@unboxed
type flexWrap =
  | @as("wrap") Wrap
  | @as("nowrap") Nowrap
  | @as("wrap-reverse") WrapReverse
  | Raw(string)

@unboxed
type overflow =
  | @as("visible") Visible
  | @as("hidden") Hidden
  | @as("scroll") Scroll
  | @as("auto") Auto
  | @as("clip") Clip
  | Raw(string)

@unboxed
type boxSizing =
  | @as("border-box") BorderBox
  | @as("content-box") ContentBox
  | Raw(string)

@unboxed
type cursor =
  | @as("auto") Auto
  | @as("default") Default
  | @as("pointer") Pointer
  | @as("text") Text
  | @as("move") Move
  | @as("not-allowed") NotAllowed
  | @as("grab") Grab
  | @as("grabbing") Grabbing
  | Raw(string)

@unboxed
type textAlign =
  | @as("left") Left
  | @as("right") Right
  | @as("center") Center
  | @as("justify") Justify
  | @as("start") Start
  | @as("end") End
  | Raw(string)

@unboxed
type textDecoration =
  | @as("none") None
  | @as("underline") Underline
  | @as("line-through") LineThrough
  | Raw(string)

@unboxed
type fontStyle =
  | @as("normal") Normal
  | @as("italic") Italic
  | Raw(string)

@unboxed
type fontVariantNumeric =
  | @as("normal") Normal
  | @as("tabular-nums") TabularNums
  | Raw(string)

@unboxed
type whiteSpace =
  | @as("normal") Normal
  | @as("nowrap") Nowrap
  | @as("pre") Pre
  | @as("pre-wrap") PreWrap
  | @as("pre-line") PreLine
  | Raw(string)

@unboxed
type userSelect =
  | @as("none") None
  | @as("auto") Auto
  | @as("text") Text
  | @as("all") All
  | Raw(string)

@unboxed
type listStyle =
  | @as("none") None
  | Raw(string)

@unboxed
type visibility =
  | @as("visible") Visible
  | @as("hidden") Hidden
  | Raw(string)

@unboxed
type pointerEvents =
  | @as("auto") Auto
  | @as("none") None
  | Raw(string)

type rec t = {
  // Layout
  display?: display,
  position?: position,
  top?: length,
  right?: length,
  bottom?: length,
  left?: length,
  inset?: length,
  zIndex?: int,
  boxSizing?: boxSizing,
  overflow?: overflow,
  overflowX?: overflow,
  overflowY?: overflow,
  visibility?: visibility,
  aspectRatio?: string,
  clip?: string,
  insetInline?: length,
  insetBlock?: length,
  insetInlineStart?: length,
  insetInlineEnd?: length,
  insetBlockStart?: length,
  insetBlockEnd?: length,
  anchorName?: string,
  positionAnchor?: string,
  positionArea?: string,
  positionTry?: string,
  positionTryFallbacks?: string,
  isolation?: string,
  // Size
  width?: length,
  height?: length,
  minWidth?: length,
  maxWidth?: length,
  minHeight?: length,
  maxHeight?: length,
  inlineSize?: length,
  blockSize?: length,
  minInlineSize?: length,
  maxInlineSize?: length,
  minBlockSize?: length,
  maxBlockSize?: length,
  // Spacing
  margin?: length,
  marginTop?: length,
  marginRight?: length,
  marginBottom?: length,
  marginLeft?: length,
  padding?: length,
  paddingTop?: length,
  paddingRight?: length,
  paddingBottom?: length,
  paddingLeft?: length,
  marginInline?: length,
  marginBlock?: length,
  marginInlineStart?: length,
  marginInlineEnd?: length,
  marginBlockStart?: length,
  marginBlockEnd?: length,
  paddingInline?: length,
  paddingBlock?: length,
  paddingInlineStart?: length,
  paddingInlineEnd?: length,
  paddingBlockStart?: length,
  paddingBlockEnd?: length,
  gap?: length,
  rowGap?: length,
  columnGap?: length,
  // Flex and grid
  flex?: string,
  flexDirection?: flexDirection,
  flexWrap?: flexWrap,
  flexGrow?: float,
  flexShrink?: float,
  flexBasis?: length,
  order?: int,
  alignItems?: align,
  alignSelf?: align,
  justifyItems?: align,
  justifySelf?: align,
  justifyContent?: justify,
  alignContent?: justify,
  placeItems?: string,
  gridTemplateColumns?: string,
  gridTemplateRows?: string,
  gridTemplateAreas?: string,
  gridAutoFlow?: string,
  gridAutoColumns?: string,
  gridAutoRows?: string,
  gridArea?: string,
  gridColumn?: string,
  gridRow?: string,
  // Text
  font?: string,
  fontFamily?: string,
  fontSize?: length,
  fontWeight?: int,
  fontStyle?: fontStyle,
  fontVariantNumeric?: fontVariantNumeric,
  lineHeight?: float,
  letterSpacing?: length,
  textAlign?: textAlign,
  textDecoration?: textDecoration,
  textTransform?: string,
  whiteSpace?: whiteSpace,
  textOverflow?: string,
  textWrap?: string,
  overflowWrap?: string,
  textUnderlineOffset?: length,
  verticalAlign?: string,
  captionSide?: string,
  color?: color,
  // Box
  background?: string,
  backgroundColor?: color,
  border?: string,
  borderTop?: string,
  borderRight?: string,
  borderBottom?: string,
  borderLeft?: string,
  borderInline?: string,
  borderBlock?: string,
  borderInlineStart?: string,
  borderInlineEnd?: string,
  borderBlockStart?: string,
  borderBlockEnd?: string,
  borderColor?: color,
  borderWidth?: length,
  borderRadius?: length,
  outline?: string,
  outlineOffset?: length,
  boxShadow?: string,
  opacity?: float,
  borderCollapse?: string,
  borderSpacing?: length,
  colorScheme?: string,
  accentColor?: color,
  // Lists and interaction
  listStyle?: listStyle,
  cursor?: cursor,
  userSelect?: userSelect,
  pointerEvents?: pointerEvents,
  appearance?: string,
  overscrollBehavior?: string,
  resize?: string,
  // Motion
  transform?: string,
  translate?: string,
  scale?: string,
  transformOrigin?: string,
  transition?: string,
  animation?: string,
  animationName?: keyframes,
  animationDuration?: string,
  animationTimingFunction?: string,
  animationIterationCount?: string,
  // Generated content and SVG
  content?: string,
  counterReset?: string,
  counterIncrement?: string,
  fill?: color,
  stroke?: color,
  // Custom properties set by this block (`Theme.accent` to another variable's value, say)
  vars?: array<(var, string)>,
  // Nested blocks
  hover?: t,
  focus?: t,
  focusVisible?: t,
  focusWithin?: t,
  active?: t,
  visited?: t,
  disabled?: t,
  checked?: t,
  firstChild?: t,
  lastChild?: t,
  placeholder?: t,
  before?: t,
  after?: t,
  selectors?: array<(string, t)>,
  media?: array<condition>,
}
/** An at-rule block: `media`, `supports` or `container`. */
and condition = {
  at: string,
  style: t,
}

/** A keyframe of `keyframes`: `~at="from"`, `"to"` or a percentage, `"50%"`. */
type frame = {at: string, style: t}

/** A class name for `css`. In a top-level `let` only (see above). */
let class: (~layer: string=?, t) => string

/**
`css` itself: a nested block (`hover: Css.style({...})`), or a fragment to spread into others
(`let base = Css.style({...})`, then `Css.class({...base, color: ...})`). Compiles to nothing.
*/
external style: t => t = "%identity"

/** Rules for `selector`, wherever the file's stylesheet is loaded (`body`, `*, *::before`, ...). */
let global: (~selector: string, ~layer: string=?, t) => unit

/**
A CSS custom property, declared on `:where(:root)` with the value `initial`: with no specificity,
so a value set for it anywhere else (`:root` in another file's sheet, an element's class or `style`)
wins whatever order the sheets load in. A component library's defaults, overridden by an app's.
*/
let var: string => var

/** An animation's keyframes, and its name, for `animationName`. */
let keyframes: (~layer: string=?, array<frame>) => keyframes

let frame: (~at: string, t) => frame

/** `@media <query>`, around `style` as a nested block. */
let media: (~query: string, t) => condition

/** `@supports <condition>`. */
let supports: (~condition: string, t) => condition

/** `@container <query>`. */
let container: (~query: string, t) => condition

/** Custom properties for a `style` prop, set at run time: `style={Css.vars([(Theme.accent, c)])}`. */
let vars: array<(var, string)> => dict<string>

/** A variable's name, `--...`, for code that sets it some other way. */
let varName: var => string

/** An animation's name. */
let keyframesName: keyframes => string

/** Class names, joined by spaces, empty ones left out. */
let cx: array<string> => string

/** The `Some` class names, joined by spaces. */
let cxOpt: array<option<string>> => string

/**
What `ppx_weft` turns the calls above into: each with its name (the readable part, then the file's
sheet id, `SheetId`), and its definition in a function, called only when the CSS is extracted. The
Vite plugin replaces each call with its name before bundling. Not for use by hand.
*/
module Internal: {
  /** What extraction finds: each registration, in the order the files' top levels run. */
  type registration =
    | Class({name: string, layer: option<string>, define: unit => t})
    | Global({name: string, selector: string, layer: option<string>, define: unit => t})
    | Var({name: string, initial: unit => string})
    | Keyframes({name: string, layer: option<string>, define: unit => array<frame>})

  let class_: (string, ~layer: string=?, unit => t) => string
  let global_: (string, ~selector: string, ~layer: string=?, unit => t) => unit
  let var_: (string, unit => string) => var
  let keyframes_: (string, ~layer: string=?, unit => array<frame>) => keyframes

  /**
  Starts recording registrations (`Extract.start`), in this copy of the module: the files must
  import the same one. A second call starts over.
  */
  let record: unit => unit

  /** Stops recording, and gives what was recorded. */
  let recorded: unit => array<registration>
}
