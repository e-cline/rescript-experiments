/*** An error boundary (it has to be an entrypoint: its fallback is a function). */

module Ui = WeftUi
module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = (~children: Weft.Element.t) =>
  <Weft.ErrorBoundary
    fallback={(~error, ~reset as _) =>
      <Ui.Alert.Root tone=#danger dataId="error-box">
        <Ui.Alert.Description>
          {Jsx.string("Couldn't show this: " ++ Weft.ErrorBoundary.message(error))}
        </Ui.Alert.Description>
      </Ui.Alert.Root>}
  >
    children
  </Weft.ErrorBoundary>
