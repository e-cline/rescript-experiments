/***
The sign-in dialog, opened from anywhere (`Store.openSignIn`): weft_ui's `Dialog`, controlled by the
store, so it's modal (the page behind it inert), its name field takes the focus as it opens, and
Escape or a click outside closes it. It's in the shell's place in the tree, so it has the page's
context (the navigation it refreshes, the RPC client).
*/

module Ui = WeftUi
module Jsx = WeftDom.Jsx

@weft.component
let make = () => {
  let isOpen = WeftSignals.SignalHooks.useSignal(Signals.Atom.toSignal(Store.signInOpen))
  let navigation = WeftServer.Navigation.useNavigation()
  <Ui.Dialog.Root
    open_=isOpen onOpenChange={open_ => open_ ? Store.openSignIn() : Store.closeSignIn()}
  >
    <Ui.Dialog.Popup size=#sm dataId="signin-dialog">
      <Ui.Dialog.Title> {Jsx.string("Sign in")} </Ui.Dialog.Title>
      <Ui.Dialog.Description>
        {Jsx.string("With your name: there's no password, it's a demo.")}
      </Ui.Dialog.Description>
      <SignInFields
        autoFocus=true
        onSignedIn={name => {
          Store.closeSignIn()
          Store.toast(`Signed in as ${name}`)
          navigation->WeftServer.Navigation.refresh->ignore
        }}
      />
      <Ui.Dialog.Footer>
        <Ui.Dialog.Close dataId="signin-close" variant=#ghost>
          {Jsx.string("Close")}
        </Ui.Dialog.Close>
      </Ui.Dialog.Footer>
    </Ui.Dialog.Popup>
  </Ui.Dialog.Root>
}
