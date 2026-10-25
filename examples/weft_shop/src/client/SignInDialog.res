/***
The sign-in dialog, opened from anywhere (`Store.openSignIn`): rendered into a layer at the end of
`<body>` (a portal), while it stays in the shell's place in the tree, so it has the page's context
(the navigation it refreshes, the RPC client). Its name field takes the focus as it opens; Escape,
or a click outside, closes it.

Only ever open in the browser: the server renders it closed, so it never touches `document` there.
*/

open WeftCss

module Styles = {
  let overlay = Css.class({
    position: Fixed,
    inset: Zero,
    display: Grid,
    placeItems: "center",
    backgroundColor: Hex("0006"),
  })
  let dialog = Css.class({
    width: Px(320),
    padding: Px(20),
    backgroundColor: Named("white"),
    borderRadius: Px(12),
  })
}

@weft.component
let make = () => {
  let isOpen = WeftSignals.SignalHooks.useSignal(Signals.Atom.toSignal(Store.signInOpen))
  let navigation = WeftServer.Navigation.useNavigation()
  let titleId = Weft.Hooks.useId()
  if isOpen {
    WeftDom.Portal.create(
      <div
        dataId="signin-overlay"
        className=Styles.overlay
        onClick={event =>
          if WeftDom.Dom.Event.target(event) == WeftDom.Dom.Event.currentTarget(event) {
            Store.closeSignIn()
          }}
        // On the overlay, not the document: a listener an effect adds would miss an Escape pressed
        // between the commit (which focuses the field) and the effect.
        onKeyDown={event =>
          if WeftDom.Dom.Event.key(event) == "Escape" {
            Store.closeSignIn()
          }}
      >
        <div
          dataId="signin-dialog"
          className=Styles.dialog
          role="dialog"
          ariaModal="true"
          ariaLabelledby=titleId
        >
          <h2 id=titleId> {WeftDom.Jsx.string("Sign in")} </h2>
          <SignInFields
            autoFocus=true
            onSignedIn={name => {
              Store.closeSignIn()
              Store.toast(`Signed in as ${name}`)
              navigation->WeftServer.Navigation.refresh->ignore
            }}
          />
          <button dataId="signin-close" onClick={_ => Store.closeSignIn()}>
            {WeftDom.Jsx.string("Close")}
          </button>
        </div>
      </div>,
      ~container=WeftDom.Dom.document->WeftDom.Dom.body,
    )
  } else {
    WeftDom.Jsx.null
  }
}
