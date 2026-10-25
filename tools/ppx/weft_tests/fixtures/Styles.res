/***
Styles at every depth: each call gets a name (the file's module, the modules inside it, the binding;
`global<n>` for globals) ending in this file's sheet id, and its definition in a function. The file
starts with `'use weft css'`.
*/
open WeftCss

let ink = Css.var("#1d1b19")

Css.global(~selector="body", {margin: Zero, color: Var(ink)})

let _ = Css.global(~selector="a", ~layer="app.reset", {color: CurrentColor})

let fadeIn = Css.keyframes([
  Css.frame(~at="from", {opacity: 0.}),
  Css.frame(~at="to", {opacity: 1.}),
])

let base = Css.style({padding: Px(10), borderRadius: Px(8)})

module Card = {
  let card = Css.class({
    ...base,
    animationName: fadeIn,
    hover: Css.style({color: Var(ink)}),
    selectors: [("h2", Css.style({margin: Zero}))],
  })

  module Title = {
    let title = Css.class(~layer="app.overrides", {fontWeight: 600})
  }
}

/** With the package's namespace written out. */
let prefixed: string = WeftCss.Css.class({display: Grid})
