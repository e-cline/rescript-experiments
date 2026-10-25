# @e-cline/weft_css

Styles for Weft, written in ReScript next to the components that use them, extracted into a
stylesheet per file at build time, and sent to each page only when something on it uses them: the
first page's shell with its stylesheets in its head, each part streamed in after it shown only once
its own have loaded, and a page navigated to (or refetched) only once its have. Server components'
styles reach the browser as CSS, never as code. With
[`weft_vite_plugin`](../../tools/weft_vite_plugin) (`weft()`, or `weftCss()` for an app without a
server). The design is [docs/weft_css_plan.md](../../docs/weft_css_plan.md);
[`weft_shop`](../../examples/weft_shop) and [`weft_app`](../../examples/weft_app) use it.

The API follows [rescript-css](https://github.com/jderochervlk/rescript-css)'s.

```rescript
open WeftCss

module Theme = {
  let accent = Css.var("#9a4b22")
}

module Styles = {
  let button = Css.class({
    display: InlineFlex,
    gap: Rem(0.5),
    padding: Pair(Px(6), Px(12)),
    color: Named("white"),
    backgroundColor: Var(Theme.accent),
    borderRadius: Px(6),
    hover: Css.style({opacity: 0.9}),
    selectors: [("&[aria-pressed=\"true\"]", Css.style({outline: "2px solid currentColor"}))],
    media: [Css.media(~query="(max-width: 720px)", {padding: Px(4)})],
  })
}

<button className=Styles.button> ... </button>
```

## Installing

Needs ReScript 12, and [`ppx_weft`](../../tools/ppx/weft), which names each style: add
`@e-cline/weft_css` to the `dependencies` in your `rescript.json`, and `"@e-cline/ppx_weft/ppx"` to
its `ppx-flags`. The modules are `WeftCss.Css` (the API), `WeftCss.SheetId` and `WeftCss.Extract`
(what the Vite plugin uses), and `WeftCss.Sheets` (loading stylesheets in the browser, which
`WeftServer.Decoder` does for the rows that need them).

## Using it

- **`Css.class(css)`**: a class name. **`Css.style(css)`**: a nested block, or a fragment to spread
  into others (`{...base, color: ...}`). **`Css.global(~selector, css)`**: rules for any selector.
  **`Css.var(initial)`**: a custom property, for `Var(...)` and `Css.vars` (a `style` prop's custom
  properties, set at run time). **`Css.keyframes([Css.frame(~at, css)])`**: an animation, for
  `animationName`. `Css.cx`/`Css.cxOpt` join class names.
- A `css` is a record of optional fields, one per property, in camel case. Keywords are constructors
  (`InlineFlex`, `SpaceBetween`), lengths are `Px(int)`, `Rem(float)`, `Pct(float)` and the rest,
  with `Pair` and `Four` for shorthands; every value type has `Raw(string)`, and properties too
  varied to type (`border`, `transition`, `gridTemplateColumns`) are strings.
- **Styles are static**: they go in `let`s at a module's top level, where `ppx_weft` names them. For
  what changes at run time, use a CSS variable, a data attribute and a `selectors` rule, or a class
  per variant.
- Classes are in the cascade layer `weft.components`, globals and variables in `weft.base` (or
  `~layer`). Across files, rules in one layer have no order to rely on: compose fragments rather
  than stacking conflicting classes.
