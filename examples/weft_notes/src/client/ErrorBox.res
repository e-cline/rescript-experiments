/*** An error boundary (it has to be an entrypoint: its fallback is a function). */

@weft.component({kind: Entrypoint})
let make = (~children: Weft.Element.t) =>
  <Weft.ErrorBoundary
    fallback={(~error, ~reset as _) =>
      <p id="error-box">
        {WeftDom.Jsx.string("Couldn't show this: " ++ Weft.ErrorBoundary.message(error))}
      </p>}
  >
    children
  </Weft.ErrorBoundary>
