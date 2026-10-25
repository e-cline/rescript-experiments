/***
A list: items one under the other, `divided` by lines, or a gap apart. Without `markers` (the
default), it has no bullets or numbers, and keeps its list role (`role="list"`), which Safari drops
from a list styled without them.

Static: a server component can render it.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let list = Css.class(~layer, {margin: Zero, padding: Zero, display: Flex, flexDirection: Column})
  let bare = Css.class(~layer, {listStyle: None})
  let markers = Css.class(~layer, {paddingInlineStart: Em(1.5)})
  let divided = Css.class(
    ~layer,
    {
      selectors: [
        ("& > li", Css.style({paddingBlock: Var(Tokens.spaceMd)})),
        ("& > li:first-child", Css.style({paddingBlockStart: Zero})),
        ("& > li:last-child", Css.style({paddingBlockEnd: Zero})),
        ("& > li + li", Css.style({borderTop: `1px solid ${Tokens.value(Tokens.border)}`})),
      ],
    },
  )
}

module Root = {
  @weft.component
  let make = (
    ~as_: [#ul | #ol]=#ul,
    ~divided=false,
    ~gap: Variants.space=#none,
    ~markers=false,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~ariaLabel=?,
    ~ariaLabelledby=?,
    ~attrs: WeftDom.DomProps.props={},
    ~children=?,
  ) =>
    Host.element(
      (as_ :> string),
      {
        ...attrs,
        ?id,
        className: Host.classes(
          Array.concat(
            [Styles.list, markers ? Styles.markers : Styles.bare, Stack.gapClass(gap)],
            divided ? [Styles.divided] : [],
          ),
          className,
        ),
        role: ?(markers ? None : Some("list")),
        ?style,
        ?dataId,
        ?ariaLabel,
        ?ariaLabelledby,
        ?children,
      },
    )
}

module Item = {
  @weft.component
  let make = (~id=?, ~className=?, ~style=?, ~dataId=?, ~children=?) =>
    <li ?id className=?className ?style ?dataId ?children />
}
