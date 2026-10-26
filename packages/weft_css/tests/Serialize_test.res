open Vitest

describe("declarations", () => {
  test("writes properties in kebab case, keywords as CSS has them", t => {
    t
    ->expect(
      Serialize.declarations({
        display: InlineFlex,
        justifyContent: SpaceBetween,
        alignItems: FlexStart,
        flexWrap: Nowrap,
        boxSizing: BorderBox,
        fontVariantNumeric: TabularNums,
        cursor: NotAllowed,
      }),
    )
    ->Expect.toEqual([
      "display: inline-flex",
      "box-sizing: border-box",
      "flex-wrap: nowrap",
      "align-items: flex-start",
      "justify-content: space-between",
      "font-variant-numeric: tabular-nums",
      "cursor: not-allowed",
    ])
  })

  test("writes lengths, colours, numbers and strings", t => {
    let accent: Css.var = %raw(`"--Theme-accent_waaaaaa"`)
    t
    ->expect(
      Serialize.declarations({
        width: Pct(50.),
        maxWidth: Px(1100),
        margin: Pair(Zero, Auto),
        padding: Four(Px(4), Rem(0.5), Em(1.25), Ch(2.)),
        gap: Calc("1rem + 2px"),
        fontSize: Var(accent),
        lineHeight: 1.5,
        zIndex: 5,
        opacity: 0.6,
        color: Hex("1d1b19"),
        backgroundColor: Rgba(0, 0, 0, 0.4),
        borderColor: CurrentColor,
        outline: "2px solid currentColor",
        fill: Var(accent),
        stroke: Raw("context-stroke"),
        display: Raw("flow-root"),
      }),
    )
    ->Expect.toEqual([
      "display: flow-root",
      "z-index: 5",
      "width: 50%",
      "max-width: 1100px",
      "margin: 0 auto",
      "padding: 4px 0.5rem 1.25em 2ch",
      "gap: calc(1rem + 2px)",
      "font-size: var(--Theme-accent_waaaaaa)",
      "line-height: 1.5",
      "color: #1d1b19",
      "background-color: rgb(0 0 0 / 0.4)",
      "border-color: currentColor",
      "outline: 2px solid currentColor",
      "opacity: 0.6",
      "fill: var(--Theme-accent_waaaaaa)",
      "stroke: context-stroke",
    ])
  })

  test("writes logical properties, anchor positioning and the rest", t => {
    t
    ->expect(
      Serialize.declarations({
        insetInlineEnd: Zero,
        anchorName: "--trigger",
        positionAnchor: "--trigger",
        positionArea: "bottom span-right",
        positionTryFallbacks: "flip-block",
        inlineSize: Pct(100.),
        maxBlockSize: Vh(80.),
        paddingInline: Px(12),
        marginBlockStart: Rem(1.),
        textOverflow: "ellipsis",
        borderInlineStart: "2px solid",
        accentColor: Hex("2563eb"),
        borderStartEndRadius: Zero,
        appearance: "none",
        translate: "0 4px",
      }),
    )
    ->Expect.toEqual([
      "inset-inline-end: 0",
      "anchor-name: --trigger",
      "position-anchor: --trigger",
      "position-area: bottom span-right",
      "position-try-fallbacks: flip-block",
      "inline-size: 100%",
      "max-block-size: 80vh",
      "margin-block-start: 1rem",
      "padding-inline: 12px",
      "text-overflow: ellipsis",
      "border-inline-start: 2px solid",
      "border-start-end-radius: 0",
      "accent-color: #2563eb",
      "appearance: none",
      "translate: 0 4px",
    ])
  })

  test("puts the block's own custom properties first", t => {
    let ink: Css.var = %raw(`"--Theme-ink_waaaaaa"`)
    t
    ->expect(Serialize.declarations({color: Var(ink), vars: [(ink, "#fff")]}))
    ->Expect.toEqual(["--Theme-ink_waaaaaa: #fff", "color: var(--Theme-ink_waaaaaa)"])
  })
})

describe("nest", () => {
  test("puts the parent in place of `&`, or makes a descendant", t => {
    t->expect(Serialize.nest(~parent=".a", "&:hover"))->Expect.toBe(".a:hover")
    t->expect(Serialize.nest(~parent=".a", "li"))->Expect.toBe(".a li")
    t->expect(Serialize.nest(~parent=".a", "& + &"))->Expect.toBe(".a + .a")
    t->expect(Serialize.nest(~parent=".a", ".dark &"))->Expect.toBe(".dark .a")
  })

  test("crosses selector lists, keeping commas in brackets and strings whole", t => {
    t
    ->expect(Serialize.nest(~parent=".a, .b", "&:is(p, li), [title=\"x,y\"]"))
    ->Expect.toBe(`.a:is(p, li), .a [title="x,y"], .b:is(p, li), .b [title="x,y"]`)
  })
})

describe("rules", () => {
  test("writes the block, then its nested blocks, at-rules around theirs", t => {
    t
    ->expect(
      Serialize.rules(
        ~selector=".card",
        {
          padding: Px(10),
          hover: Css.style({opacity: 0.9}),
          selectors: [
            ("&[aria-busy=\"true\"]", Css.style({opacity: 0.6})),
            ("h2", Css.style({margin: Zero, focusVisible: Css.style({outline: "none"})})),
          ],
          media: [
            Css.media(
              ~query="(max-width: 720px)",
              {padding: Px(4), selectors: [("p", Css.style({display: None}))]},
            ),
          ],
        },
      ),
    )
    ->Expect.toBe(`.card {
  padding: 10px;
}
.card:hover {
  opacity: 0.9;
}
.card[aria-busy="true"] {
  opacity: 0.6;
}
.card h2 {
  margin: 0;
}
.card h2:focus-visible {
  outline: none;
}
@media (max-width: 720px) {
  .card {
    padding: 4px;
  }
  .card p {
    display: none;
  }
}
`)
  })

  test("leaves out empty blocks", t => {
    t
    ->expect(
      Serialize.rules(
        ~selector=".a",
        {hover: Css.style({}), media: [Css.supports(~condition="(gap: 1px)", {})]},
      ),
    )
    ->Expect.toBe("")
  })
})

describe("keyframes", () => {
  test("writes each frame", t => {
    t
    ->expect(
      Serialize.keyframes(
        ~name="Fade-in_waaaaaa",
        [Css.frame(~at="from", {opacity: 0.}), Css.frame(~at="to", {opacity: 1.})],
      ),
    )
    ->Expect.toBe(`@keyframes Fade-in_waaaaaa {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}
`)
  })
})
