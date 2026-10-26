/***
The look text controls share (`Input`, `Textarea`, `Select`, `NumberField`'s input), as fragments
each spreads into a class of its own: a border with 3:1 contrast, the focus ring, and a red border
once it's `aria-invalid`.
*/
open WeftCss

let base = () =>
  Css.style({
    boxSizing: BorderBox,
    inlineSize: Pct(100.),
    minWidth: Zero,
    font: "inherit",
    fontSize: Var(Tokens.textSm),
    lineHeight: 1.4,
    color: Var(Tokens.fg),
    backgroundColor: Var(Tokens.surface),
    border: `1px solid ${Tokens.value(Tokens.borderStrong)}`,
    borderRadius: Var(Tokens.radiusMd),
    transition: `border-color ${Tokens.value(Tokens.durationFast)}`,
    placeholder: Css.style({color: Var(Tokens.fgMuted), opacity: 1.}),
    focusVisible: Css.style({
      outline: `2px solid ${Tokens.value(Tokens.focusRing)}`,
      outlineOffset: Zero,
      borderColor: Var(Tokens.focusRing),
    }),
    disabled: Css.style({
      opacity: 0.6,
      cursor: NotAllowed,
      backgroundColor: Var(Tokens.surfaceMuted),
    }),
    selectors: [
      ("&[aria-invalid=\"true\"]", Css.style({borderColor: Var(Tokens.danger)})),
      (
        "&[aria-invalid=\"true\"]:focus-visible",
        Css.style({outline: `2px solid ${Tokens.value(Tokens.danger)}`}),
      ),
    ],
  })

/** A one-line control's height and padding, by size. */
let sized = (size: Variants.size) =>
  switch size {
  | #sm => Css.style({minHeight: Var(Tokens.controlSm), padding: Pair(Px(2), Var(Tokens.spaceSm))})
  | #md => Css.style({minHeight: Var(Tokens.controlMd), padding: Pair(Px(4), Var(Tokens.spaceMd))})
  | #lg =>
    Css.style({
      minHeight: Var(Tokens.controlLg),
      padding: Pair(Px(6), Var(Tokens.spaceMd)),
      fontSize: Var(Tokens.textMd),
    })
  }
