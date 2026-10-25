/***
A small label: a status, a count, a tag. `Badge.className()` gives a link (a chip) its look.

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let badge = Css.class(
    ~layer,
    {
      display: InlineFlex,
      alignItems: Center,
      gap: Var(Tokens.spaceXs),
      border: "1px solid transparent",
      fontWeight: 500,
      lineHeight: 1.4,
      whiteSpace: Nowrap,
      textDecoration: None,
      verticalAlign: "middle",
      focusVisible: Tokens.focusVisible(),
    },
  )
  let sm = Css.class(
    ~layer,
    {fontSize: Var(Tokens.textXs), padding: Pair(Px(0), Var(Tokens.spaceSm))},
  )
  let md = Css.class(
    ~layer,
    {fontSize: Var(Tokens.textSm), padding: Pair(Px(2), Var(Tokens.spaceSm))},
  )
  let rounded = Css.class(~layer, {borderRadius: Var(Tokens.radiusSm)})
  let pill = Css.class(~layer, {borderRadius: Var(Tokens.radiusFull)})

  let softNeutral = Css.class(
    ~layer,
    {color: Var(Tokens.neutralSoftFg), backgroundColor: Var(Tokens.neutralSoft)},
  )
  let softAccent = Css.class(
    ~layer,
    {color: Var(Tokens.accentSoftFg), backgroundColor: Var(Tokens.accentSoft)},
  )
  let softSuccess = Css.class(
    ~layer,
    {color: Var(Tokens.successSoftFg), backgroundColor: Var(Tokens.successSoft)},
  )
  let softWarning = Css.class(
    ~layer,
    {color: Var(Tokens.warningSoftFg), backgroundColor: Var(Tokens.warningSoft)},
  )
  let softDanger = Css.class(
    ~layer,
    {color: Var(Tokens.dangerSoftFg), backgroundColor: Var(Tokens.dangerSoft)},
  )

  let solidNeutral = Css.class(~layer, {color: Var(Tokens.bg), backgroundColor: Var(Tokens.fg)})
  let solidAccent = Css.class(
    ~layer,
    {color: Var(Tokens.accentFg), backgroundColor: Var(Tokens.accent)},
  )
  let solidSuccess = Css.class(
    ~layer,
    {color: Var(Tokens.successFg), backgroundColor: Var(Tokens.success)},
  )
  let solidWarning = Css.class(
    ~layer,
    {color: Var(Tokens.warningFg), backgroundColor: Var(Tokens.warning)},
  )
  let solidDanger = Css.class(
    ~layer,
    {color: Var(Tokens.dangerFg), backgroundColor: Var(Tokens.danger)},
  )

  let outline = Css.class(~layer, {backgroundColor: Transparent, borderColor: CurrentColor})
  let outlineNeutral = Css.class(
    ~layer,
    {color: Var(Tokens.fgMuted), borderColor: Var(Tokens.border)},
  )
  let outlineAccent = Css.class(~layer, {color: Var(Tokens.accent)})
  let outlineSuccess = Css.class(~layer, {color: Var(Tokens.success)})
  let outlineWarning = Css.class(~layer, {color: Var(Tokens.warning)})
  let outlineDanger = Css.class(~layer, {color: Var(Tokens.danger)})

  /** A badge that's a link: its border darkens on hover. */
  let link = Css.class(
    ~layer,
    {cursor: Pointer, hover: Css.style({borderColor: Var(Tokens.borderStrong)})},
  )
}

type variant = [#soft | #solid | #outline]

/** A badge's classes, for an element of your own (a link that's a chip). */
let className = (
  ~tone: Variants.tone=#neutral,
  ~variant: variant=#soft,
  ~size: [#sm | #md]=#md,
  ~shape: [#rounded | #pill]=#pill,
  ~link=false,
  (),
) =>
  Css.cxOpt([
    Some(Styles.badge),
    Some(size == #sm ? Styles.sm : Styles.md),
    Some(shape == #pill ? Styles.pill : Styles.rounded),
    variant == #outline ? Some(Styles.outline) : None,
    Some(
      switch (variant, tone) {
      | (#soft, #neutral) => Styles.softNeutral
      | (#soft, #accent) => Styles.softAccent
      | (#soft, #success) => Styles.softSuccess
      | (#soft, #warning) => Styles.softWarning
      | (#soft, #danger) => Styles.softDanger
      | (#solid, #neutral) => Styles.solidNeutral
      | (#solid, #accent) => Styles.solidAccent
      | (#solid, #success) => Styles.solidSuccess
      | (#solid, #warning) => Styles.solidWarning
      | (#solid, #danger) => Styles.solidDanger
      | (#outline, #neutral) => Styles.outlineNeutral
      | (#outline, #accent) => Styles.outlineAccent
      | (#outline, #success) => Styles.outlineSuccess
      | (#outline, #warning) => Styles.outlineWarning
      | (#outline, #danger) => Styles.outlineDanger
      },
    ),
    link ? Some(Styles.link) : None,
  ])

@weft.component
let make = (
  ~tone: Variants.tone=#neutral,
  ~variant: variant=#soft,
  ~size: [#sm | #md]=#md,
  ~shape: [#rounded | #pill]=#pill,
  ~id=?,
  ~className as extra=?,
  ~style=?,
  ~dataId=?,
  ~ariaLabel=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=?,
) =>
  <span
    {...attrs}
    ?id
    className={Host.classes([className(~tone, ~variant, ~size, ~shape, ())], extra)}
    ?style
    ?dataId
    ?ariaLabel
    dataVariant={(tone :> string)}
    ?children
  />
