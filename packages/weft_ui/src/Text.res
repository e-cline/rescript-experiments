/***
Text: a paragraph by default (`as_` for a `<span>`, `<small>`, ...), in a `tone`, `size` and
`weight`. Without a `size`, it's the size of what's around it.

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let text = Css.class(~layer, {margin: Zero})
  let muted = Css.class(~layer, {color: Var(Tokens.fgMuted)})
  let accent = Css.class(~layer, {color: Var(Tokens.accent)})
  let success = Css.class(~layer, {color: Var(Tokens.success)})
  let warning = Css.class(~layer, {color: Var(Tokens.warning)})
  let danger = Css.class(~layer, {color: Var(Tokens.danger)})
  let xs = Css.class(~layer, {fontSize: Var(Tokens.textXs)})
  let sm = Css.class(~layer, {fontSize: Var(Tokens.textSm)})
  let md = Css.class(~layer, {fontSize: Var(Tokens.textMd)})
  let lg = Css.class(~layer, {fontSize: Var(Tokens.textLg)})
  let normal = Css.class(~layer, {fontWeight: 400})
  let medium = Css.class(~layer, {fontWeight: 500})
  let semibold = Css.class(~layer, {fontWeight: 600})
  let bold = Css.class(~layer, {fontWeight: 700})
  let italic = Css.class(~layer, {fontStyle: Italic})
  let numeric = Css.class(~layer, {fontVariantNumeric: TabularNums})
  let truncate = Css.class(
    ~layer,
    {overflow: Hidden, textOverflow: "ellipsis", whiteSpace: Nowrap, minWidth: Zero},
  )
}

type tone = [#default | #muted | #accent | #success | #warning | #danger]
type size = [#xs | #sm | #md | #lg]
type weight = [#normal | #medium | #semibold | #bold]

/** Text's classes, for an element of your own. */
let className = (
  ~tone: tone=#default,
  ~size: option<size>=?,
  ~weight: option<weight>=?,
  ~italic=false,
  ~numeric=false,
  ~truncate=false,
  (),
) =>
  Css.cxOpt([
    Some(Styles.text),
    switch tone {
    | #default => None
    | #muted => Some(Styles.muted)
    | #accent => Some(Styles.accent)
    | #success => Some(Styles.success)
    | #warning => Some(Styles.warning)
    | #danger => Some(Styles.danger)
    },
    size->Option.map(size =>
      switch size {
      | #xs => Styles.xs
      | #sm => Styles.sm
      | #md => Styles.md
      | #lg => Styles.lg
      }
    ),
    weight->Option.map(weight =>
      switch weight {
      | #normal => Styles.normal
      | #medium => Styles.medium
      | #semibold => Styles.semibold
      | #bold => Styles.bold
      }
    ),
    italic ? Some(Styles.italic) : None,
    numeric ? Some(Styles.numeric) : None,
    truncate ? Some(Styles.truncate) : None,
  ])

@weft.component
let make = (
  ~as_: [#p | #span | #div | #small | #strong | #em | #label]=#p,
  ~tone: tone=#default,
  ~size: option<size>=?,
  ~weight: option<weight>=?,
  ~italic=false,
  ~numeric=false,
  ~truncate=false,
  ~id=?,
  ~className as extra=?,
  ~style=?,
  ~dataId=?,
  ~role=?,
  ~ariaLive=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=?,
) =>
  Host.element(
    ~attrs,
    (as_ :> string),
    {
      ?id,
      className: Host.classes(
        [className(~tone, ~size?, ~weight?, ~italic, ~numeric, ~truncate, ())],
        extra,
      ),
      ?style,
      ?dataId,
      ?role,
      ?ariaLive,
      ?children,
    },
  )
