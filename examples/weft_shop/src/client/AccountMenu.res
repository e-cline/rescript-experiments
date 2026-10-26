/***
Who's signed in, and signing in (the dialog) or out (the `auth.signOut` RPC, then a refresh): signed
in, a menu (weft_ui's `Menu`) with the account's page and signing out.
*/

module Ui = WeftUi

@weft.component({kind: Entrypoint})
let make = () => {
  let {user} = ShopContext.use()
  let navigation = WeftServer.Navigation.useNavigation()
  let signOut = WeftServer.Rpc.use(Api.signOut)
  <div dataId="account-menu">
    {switch user {
    | Some(name) =>
      <Ui.Menu.Root align=#end>
        <Ui.Menu.Trigger dataId="account-trigger">
          {WeftDom.Jsx.string(`Hi, ${name}`)}
        </Ui.Menu.Trigger>
        <Ui.Menu.Popup>
          <Ui.Menu.LinkItem
            href="/account"
            dataId="account-link"
            onClick={event =>
              navigation->WeftServer.Navigation.followLink(event, ~href="/account")->ignore}
          >
            {WeftDom.Jsx.string("Your account")}
          </Ui.Menu.LinkItem>
          <Ui.Menu.Separator />
          <Ui.Menu.Item
            dataId="sign-out"
            onSelect={() =>
              (
                async () =>
                  switch await signOut() {
                  | Ok() =>
                    Store.toast("Signed out")
                    await navigation->WeftServer.Navigation.refresh
                  | Error(error) => Store.toast(Api.describe(error))
                  }
              )()->ignore}
          >
            {WeftDom.Jsx.string("Sign out")}
          </Ui.Menu.Item>
        </Ui.Menu.Popup>
      </Ui.Menu.Root>
    | None =>
      <Ui.Button dataId="sign-in" onClick={_ => Store.openSignIn()}>
        {WeftDom.Jsx.string("Sign in")}
      </Ui.Button>
    }}
  </div>
}
