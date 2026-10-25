/*** An error boundary (it has to be an entrypoint: its fallback is a function). */

open WeftCss

module Styles = {
  let box = Css.class({
    marginTop: Px(24),
    padding: Pair(Px(10), Px(14)),
    borderRadius: Px(6),
    border: `1px solid ${Theme.value(Theme.danger)}`,
    color: Var(Theme.danger),
    backgroundColor: Hex("#fbf1f0"),
  })
}

@weft.component({kind: Entrypoint})
let make = (~children: Weft.Element.t) =>
  <Weft.ErrorBoundary
    fallback={(~error, ~reset as _) =>
      <p dataId="error-box" className=Styles.box>
        {WeftDom.Jsx.string("Couldn't show this: " ++ Weft.ErrorBoundary.message(error))}
      </p>}
  >
    children
  </Weft.ErrorBoundary>
