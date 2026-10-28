/***
A link. An app's own links that navigate in place (with `WeftServer.Navigation`) wear its look with
`Link.className()` (or a button's, `Button.className()`), or render this with their `onClick`.

`external` opens it in a new tab, and says so to assistive technology.

Static: a server component can render it (without `onClick`).
*/
open WeftCss
module Jsx = WeftDom.Jsx

module Styles = {
  let layer = Tokens.layer
  let link = Css.class(
    ~layer,
    {
      color: Var(Tokens.accent),
      textDecoration: Underline,
      textUnderlineOffset: Em(0.2),
      borderRadius: Px(2),
      hover: Css.style({color: Var(Tokens.accentHover)}),
      focusVisible: Tokens.focusVisible(),
    },
  )
  let inherit = Css.class(
    ~layer,
    {color: Raw("inherit"), hover: Css.style({color: Raw("inherit")})},
  )
  let muted = Css.class(
    ~layer,
    {color: Var(Tokens.fgMuted), hover: Css.style({color: Var(Tokens.fg)})},
  )
  let underlineHover = Css.class(
    ~layer,
    {textDecoration: None, hover: Css.style({textDecoration: Underline})},
  )
  let underlineNone = Css.class(
    ~layer,
    {textDecoration: None, hover: Css.style({textDecoration: None})},
  )
  let current = Css.class(
    ~layer,
    {
      selectors: [
        ("&[aria-current=\"page\"]", Css.style({fontWeight: 600, color: Var(Tokens.fg)})),
      ],
    },
  )
}

type tone = [#accent | #inherit | #muted]
type underline = [#always | #hover | #none]

/** A link's classes, for a link of your own (an app's navigating one). */
let className = (~tone: tone=#accent, ~underline: underline=#always, ()) =>
  Css.cxOpt([
    Some(Styles.link),
    switch tone {
    | #accent => None
    | #inherit => Some(Styles.inherit)
    | #muted => Some(Styles.muted)
    },
    switch underline {
    | #always => None
    | #hover => Some(Styles.underlineHover)
    | #none => Some(Styles.underlineNone)
    },
    Some(Styles.current),
  ])

@weft.component
let make = (
  ~href: string,
  ~tone: tone=#accent,
  ~underline: underline=#always,
  ~external_=false,
  ~onClick=?,
  ~ariaCurrent=?,
  ~ariaLabel=?,
  ~id=?,
  ~className as extra=?,
  ~style=?,
  ~dataId=?,
  ~attrs: WeftDom.DomProps.props={},
  ~children=?,
) =>
  Host.withAttrs(
    attrs,
    <a
      href
      ?id
      className={Host.classes([className(~tone, ~underline, ())], extra)}
      ?style
      ?dataId
      ?onClick
      ?ariaCurrent
      ?ariaLabel
      target=?{external_ ? Some("_blank") : None}
      rel=?{external_ ? Some("noopener noreferrer") : None}
    >
      {switch children {
      | Some(children) => children
      | None => Jsx.null
      }}
      {external_
        ? <VisuallyHidden> {Jsx.string(" (opens in a new tab)")} </VisuallyHidden>
        : Jsx.null}
    </a>,
  )
