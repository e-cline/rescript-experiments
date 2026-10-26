/***
What a checkbox, a radio button and a switch share: a label around the control and its text, with
an optional description under the text, and the click target the whole label.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let choice = Css.class(
    ~layer,
    {
      display: InlineFlex,
      alignItems: FlexStart,
      gap: Var(Tokens.spaceSm),
      fontSize: Var(Tokens.textSm),
      lineHeight: 1.5,
      color: Var(Tokens.fg),
      cursor: Pointer,
      selectors: [("&:has(:disabled)", Css.style({opacity: 0.6, cursor: NotAllowed}))],
    },
  )
  let text = Css.class(~layer, {display: Flex, flexDirection: Column, gap: Px(2)})
  let description = Css.class(~layer, {color: Var(Tokens.fgMuted)})
}

/** `onChange`, and `onCheckedChange` with the control's new state, as one handler, if either. */
let onChange = (~onChange, ~onCheckedChange) =>
  switch (onChange, onCheckedChange) {
  | (None, None) => None
  | _ =>
    Some(
      event => {
        onChange->Option.forEach(onChange => onChange(event))
        onCheckedChange->Option.forEach(onCheckedChange =>
          onCheckedChange(WeftDom.Dom.Event.targetChecked(event))
        )
      },
    )
  }

/** The label around `control`, its text, and the description's (`descriptionId`). */
let render = (
  ~control: Weft.Element.t,
  ~children: option<Weft.Element.t>,
  ~description: option<string>,
  ~descriptionId: string,
  ~className: option<string>,
  ~style: option<dict<string>>,
) =>
  <label className={Host.classes([Styles.choice], className)} ?style>
    control
    <span className=Styles.text>
      {children->Option.getOr(WeftDom.Jsx.null)}
      {switch description {
      | Some(description) =>
        <span id=descriptionId className=Styles.description>
          {WeftDom.Jsx.string(description)}
        </span>
      | None => WeftDom.Jsx.null
      }}
    </span>
  </label>
