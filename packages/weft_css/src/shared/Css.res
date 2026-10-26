type var = string
type keyframes = string

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
  borderStartStartRadius?: length,
  borderStartEndRadius?: length,
  borderEndStartRadius?: length,
  borderEndEndRadius?: length,
  outline?: string,
  outlineOffset?: length,
  boxShadow?: string,
  opacity?: float,
  borderCollapse?: string,
  borderSpacing?: length,
  colorScheme?: string,
  accentColor?: color,
  listStyle?: listStyle,
  cursor?: cursor,
  userSelect?: userSelect,
  pointerEvents?: pointerEvents,
  appearance?: string,
  overscrollBehavior?: string,
  resize?: string,
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
  content?: string,
  counterReset?: string,
  counterIncrement?: string,
  fill?: color,
  stroke?: color,
  vars?: array<(var, string)>,
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
and condition = {at: string, style: t}

type frame = {at: string, style: t}

let unprocessed = name =>
  JsError.throwWithMessage(
    `weft_css: Css.${name} was called directly: this file wasn't compiled with ppx_weft (add "@e-cline/ppx_weft/ppx" to its rescript.json's "ppx-flags"), or the call isn't in a top-level \`let\``,
  )

let class = (~layer as _=?, _: t) => unprocessed("class")
external style: t => t = "%identity"
let global = (~selector as _, ~layer as _=?, _: t) => unprocessed("global")
let var = _ => unprocessed("var")
let keyframes = (~layer as _=?, _) => unprocessed("keyframes")
let frame = (~at, style): frame => {at, style}
let media = (~query, style): condition => {at: `@media ${query}`, style}
let supports = (~condition, style): condition => {at: `@supports ${condition}`, style}
let container = (~query, style): condition => {at: `@container ${query}`, style}
let vars = values => Dict.fromArray(values)
let varName = var => var
let keyframesName = keyframes => keyframes
let cx = names => names->Array.filter(name => name !== "")->Array.join(" ")
let cxOpt = names => names->Array.filterMap(name => name)->cx

module Internal = {
  type registration =
    | Class({name: string, layer: option<string>, define: unit => t})
    | Global({name: string, selector: string, layer: option<string>, define: unit => t})
    | Var({name: string, initial: unit => string})
    | Keyframes({name: string, layer: option<string>, define: unit => array<frame>})

  // In this copy of the module only: the extraction imports `Extract`, and the style files, through
  // a module runner of its own, so what other copies run (a dev server's, rendering a request at
  // the same moment) isn't recorded.
  // (A flag and an array, not an option: this module's keyword types shadow `None`.)
  let recording = ref(false)
  let registrations: ref<array<registration>> = ref([])

  let add = registration =>
    if recording.contents {
      registrations.contents->Array.push(registration)
    }

  let class_ = (name, ~layer=?, define) => {
    add(Class({name, layer, define}))
    name
  }

  let global_ = (name, ~selector, ~layer=?, define) => add(Global({name, selector, layer, define}))

  let var_ = (name, initial) => {
    add(Var({name, initial}))
    name
  }

  let keyframes_ = (name, ~layer=?, define) => {
    add(Keyframes({name, layer, define}))
    name
  }

  let record = () => {
    recording := true
    registrations := []
  }

  let recorded = () => {
    let recorded = registrations.contents
    recording := false
    registrations := []
    recorded
  }
}
