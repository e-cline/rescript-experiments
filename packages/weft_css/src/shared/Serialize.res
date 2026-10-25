external keyword: 'keyword => string = "%identity"
external varName: Css.var => string = "%identity"

let number = (n: float) => Float.toString(n)

let rec length = (value: Css.length) =>
  switch value {
  | Px(n) => `${Int.toString(n)}px`
  | Rem(n) => `${number(n)}rem`
  | Em(n) => `${number(n)}em`
  | Pct(n) => `${number(n)}%`
  | Vw(n) => `${number(n)}vw`
  | Vh(n) => `${number(n)}vh`
  | Ch(n) => `${number(n)}ch`
  | Fr(n) => `${number(n)}fr`
  | Zero => "0"
  | Auto => "auto"
  | Calc(expression) => `calc(${expression})`
  | Pair(a, b) => `${length(a)} ${length(b)}`
  | Four(a, b, c, d) => `${length(a)} ${length(b)} ${length(c)} ${length(d)}`
  | Var(var) => `var(${varName(var)})`
  | Raw(text) => text
  }

let color = (value: Css.color) =>
  switch value {
  | Hex(hex) => hex->String.startsWith("#") ? hex : `#${hex}`
  | Rgb(r, g, b) => `rgb(${Int.toString(r)} ${Int.toString(g)} ${Int.toString(b)})`
  | Rgba(r, g, b, a) =>
    `rgb(${Int.toString(r)} ${Int.toString(g)} ${Int.toString(b)} / ${number(a)})`
  | Named(name) => name
  | CurrentColor => "currentColor"
  | Transparent => "transparent"
  | Var(var) => `var(${varName(var)})`
  | Raw(text) => text
  }

let declarations = (css: Css.t) => {
  let out = []
  let add = (property, value, write) =>
    switch value {
    | Some(value) => out->Array.push(`${property}: ${write(value)}`)
    | None => ()
    }
  let text = value => value
  let int = (n: int) => Int.toString(n)
  css.vars
  ->Option.getOr([])
  ->Array.forEach(((var, value)) => out->Array.push(`${varName(var)}: ${value}`))
  add("display", css.display, keyword)
  add("position", css.position, keyword)
  add("top", css.top, length)
  add("right", css.right, length)
  add("bottom", css.bottom, length)
  add("left", css.left, length)
  add("inset", css.inset, length)
  add("z-index", css.zIndex, int)
  add("box-sizing", css.boxSizing, keyword)
  add("overflow", css.overflow, keyword)
  add("overflow-x", css.overflowX, keyword)
  add("overflow-y", css.overflowY, keyword)
  add("visibility", css.visibility, keyword)
  add("aspect-ratio", css.aspectRatio, text)
  add("clip", css.clip, text)
  add("inset-inline", css.insetInline, length)
  add("inset-block", css.insetBlock, length)
  add("inset-inline-start", css.insetInlineStart, length)
  add("inset-inline-end", css.insetInlineEnd, length)
  add("inset-block-start", css.insetBlockStart, length)
  add("inset-block-end", css.insetBlockEnd, length)
  add("anchor-name", css.anchorName, text)
  add("position-anchor", css.positionAnchor, text)
  add("position-area", css.positionArea, text)
  add("position-try", css.positionTry, text)
  add("position-try-fallbacks", css.positionTryFallbacks, text)
  add("isolation", css.isolation, text)
  add("width", css.width, length)
  add("height", css.height, length)
  add("min-width", css.minWidth, length)
  add("max-width", css.maxWidth, length)
  add("min-height", css.minHeight, length)
  add("max-height", css.maxHeight, length)
  add("inline-size", css.inlineSize, length)
  add("block-size", css.blockSize, length)
  add("min-inline-size", css.minInlineSize, length)
  add("max-inline-size", css.maxInlineSize, length)
  add("min-block-size", css.minBlockSize, length)
  add("max-block-size", css.maxBlockSize, length)
  add("margin", css.margin, length)
  add("margin-top", css.marginTop, length)
  add("margin-right", css.marginRight, length)
  add("margin-bottom", css.marginBottom, length)
  add("margin-left", css.marginLeft, length)
  add("padding", css.padding, length)
  add("padding-top", css.paddingTop, length)
  add("padding-right", css.paddingRight, length)
  add("padding-bottom", css.paddingBottom, length)
  add("padding-left", css.paddingLeft, length)
  add("margin-inline", css.marginInline, length)
  add("margin-block", css.marginBlock, length)
  add("margin-inline-start", css.marginInlineStart, length)
  add("margin-inline-end", css.marginInlineEnd, length)
  add("margin-block-start", css.marginBlockStart, length)
  add("margin-block-end", css.marginBlockEnd, length)
  add("padding-inline", css.paddingInline, length)
  add("padding-block", css.paddingBlock, length)
  add("padding-inline-start", css.paddingInlineStart, length)
  add("padding-inline-end", css.paddingInlineEnd, length)
  add("padding-block-start", css.paddingBlockStart, length)
  add("padding-block-end", css.paddingBlockEnd, length)
  add("gap", css.gap, length)
  add("row-gap", css.rowGap, length)
  add("column-gap", css.columnGap, length)
  add("flex", css.flex, text)
  add("flex-direction", css.flexDirection, keyword)
  add("flex-wrap", css.flexWrap, keyword)
  add("flex-grow", css.flexGrow, number)
  add("flex-shrink", css.flexShrink, number)
  add("flex-basis", css.flexBasis, length)
  add("order", css.order, int)
  add("align-items", css.alignItems, keyword)
  add("align-self", css.alignSelf, keyword)
  add("justify-items", css.justifyItems, keyword)
  add("justify-self", css.justifySelf, keyword)
  add("justify-content", css.justifyContent, keyword)
  add("align-content", css.alignContent, keyword)
  add("place-items", css.placeItems, text)
  add("grid-template-columns", css.gridTemplateColumns, text)
  add("grid-template-rows", css.gridTemplateRows, text)
  add("grid-template-areas", css.gridTemplateAreas, text)
  add("grid-auto-flow", css.gridAutoFlow, text)
  add("grid-auto-columns", css.gridAutoColumns, text)
  add("grid-auto-rows", css.gridAutoRows, text)
  add("grid-area", css.gridArea, text)
  add("grid-column", css.gridColumn, text)
  add("grid-row", css.gridRow, text)
  add("font", css.font, text)
  add("font-family", css.fontFamily, text)
  add("font-size", css.fontSize, length)
  add("font-weight", css.fontWeight, int)
  add("font-style", css.fontStyle, keyword)
  add("font-variant-numeric", css.fontVariantNumeric, keyword)
  add("line-height", css.lineHeight, number)
  add("letter-spacing", css.letterSpacing, length)
  add("text-align", css.textAlign, keyword)
  add("text-decoration", css.textDecoration, keyword)
  add("text-transform", css.textTransform, text)
  add("white-space", css.whiteSpace, keyword)
  add("text-overflow", css.textOverflow, text)
  add("text-wrap", css.textWrap, text)
  add("overflow-wrap", css.overflowWrap, text)
  add("text-underline-offset", css.textUnderlineOffset, length)
  add("vertical-align", css.verticalAlign, text)
  add("caption-side", css.captionSide, text)
  add("color", css.color, color)
  add("background", css.background, text)
  add("background-color", css.backgroundColor, color)
  add("border", css.border, text)
  add("border-top", css.borderTop, text)
  add("border-right", css.borderRight, text)
  add("border-bottom", css.borderBottom, text)
  add("border-left", css.borderLeft, text)
  add("border-inline", css.borderInline, text)
  add("border-block", css.borderBlock, text)
  add("border-inline-start", css.borderInlineStart, text)
  add("border-inline-end", css.borderInlineEnd, text)
  add("border-block-start", css.borderBlockStart, text)
  add("border-block-end", css.borderBlockEnd, text)
  add("border-color", css.borderColor, color)
  add("border-width", css.borderWidth, length)
  add("border-radius", css.borderRadius, length)
  add("outline", css.outline, text)
  add("outline-offset", css.outlineOffset, length)
  add("box-shadow", css.boxShadow, text)
  add("opacity", css.opacity, number)
  add("border-collapse", css.borderCollapse, text)
  add("border-spacing", css.borderSpacing, length)
  add("color-scheme", css.colorScheme, text)
  add("accent-color", css.accentColor, color)
  add("list-style", css.listStyle, keyword)
  add("cursor", css.cursor, keyword)
  add("user-select", css.userSelect, keyword)
  add("pointer-events", css.pointerEvents, keyword)
  add("appearance", css.appearance, text)
  add("overscroll-behavior", css.overscrollBehavior, text)
  add("resize", css.resize, text)
  add("transform", css.transform, text)
  add("translate", css.translate, text)
  add("scale", css.scale, text)
  add("transform-origin", css.transformOrigin, text)
  add("transition", css.transition, text)
  add("animation", css.animation, text)
  add("animation-name", css.animationName, keyword)
  add("animation-duration", css.animationDuration, text)
  add("animation-timing-function", css.animationTimingFunction, text)
  add("animation-iteration-count", css.animationIterationCount, text)
  add("content", css.content, text)
  add("counter-reset", css.counterReset, text)
  add("counter-increment", css.counterIncrement, text)
  add("fill", css.fill, color)
  add("stroke", css.stroke, color)
  out
}

let indent = text =>
  text
  ->String.split("\n")
  ->Array.map(line => line === "" ? line : `  ${line}`)
  ->Array.join("\n")

let block = (selector, lines) =>
  `${selector} {\n${lines->Array.map(line => `  ${line};\n`)->Array.join("")}}\n`

// A selector list's selectors: split at the commas outside brackets, parentheses and strings.
let split = selectors => {
  let parts = []
  let start = ref(0)
  let depth = ref(0)
  let quote = ref(None)
  let i = ref(0)
  let n = String.length(selectors)
  while i.contents < n {
    let c = selectors->String.charAt(i.contents)
    switch (quote.contents, c) {
    | (Some(_), "\\") => i := i.contents + 1
    | (Some(q), c) if c === q => quote := None
    | (Some(_), _) => ()
    | (None, "\"" | "'") => quote := Some(c)
    | (None, "(" | "[") => depth := depth.contents + 1
    | (None, ")" | "]") => depth := depth.contents - 1
    | (None, ",") if depth.contents === 0 =>
      parts->Array.push(
        selectors->String.slice(~start=start.contents, ~end=i.contents)->String.trim,
      )
      start := i.contents + 1
    | (None, _) => ()
    }
    i := i.contents + 1
  }
  parts->Array.push(selectors->String.slice(~start=start.contents)->String.trim)
  parts
}

let nest = (~parent, child) =>
  split(parent)
  ->Array.flatMap(parent =>
    split(child)->Array.map(child =>
      child->String.includes("&") ? child->String.replaceAll("&", parent) : `${parent} ${child}`
    )
  )
  ->Array.join(", ")

let pseudos = (css: Css.t) => [
  ("&:hover", css.hover),
  ("&:focus", css.focus),
  ("&:focus-visible", css.focusVisible),
  ("&:focus-within", css.focusWithin),
  ("&:active", css.active),
  ("&:visited", css.visited),
  ("&:disabled", css.disabled),
  ("&:checked", css.checked),
  ("&:first-child", css.firstChild),
  ("&:last-child", css.lastChild),
  ("&::placeholder", css.placeholder),
  ("&::before", css.before),
  ("&::after", css.after),
]

let rec rules = (~selector, css: Css.t) => {
  let own = declarations(css)
  let nested =
    pseudos(css)
    ->Array.filterMap(((child, block)) =>
      block->Option.map(block => rules(~selector=nest(~parent=selector, child), block))
    )
    ->Array.concat(
      css.selectors
      ->Option.getOr([])
      ->Array.map(((child, block)) => rules(~selector=nest(~parent=selector, child), block)),
    )
    ->Array.concat(
      css.media
      ->Option.getOr([])
      ->Array.filterMap(({at, style}) =>
        switch rules(~selector, style) {
        | "" => None
        | inner => Some(`${at} {\n${indent(inner)}}\n`)
        }
      ),
    )
  (Array.length(own) > 0 ? block(selector, own) : "") ++ nested->Array.join("")
}

let keyframes = (~name, frames: array<Css.frame>) =>
  `@keyframes ${name} {\n${frames
    ->Array.map(({at, style}) => indent(block(at, declarations(style))))
    ->Array.join("")}}\n`

let root = vars =>
  Array.length(vars) > 0
    ? block(":where(:root)", vars->Array.map(((name, value)) => `${name}: ${value}`))
    : ""

let layer = (~name, text) => `@layer ${name} {\n${indent(text)}}\n`
