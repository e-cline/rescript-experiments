/*** Who's signed in, and signing in (the dialog) or out (the `auth.signOut` RPC, then a refresh). */

@weft.component({kind: Entrypoint})
let make = () => {
  let {user} = ShopContext.use()
  let navigation = WeftServer.Navigation.useNavigation()
  let signOut = WeftServer.Rpc.use(Api.signOut)
  <div id="account-menu">
    {switch user {
    | Some(name) =>
      <>
        <Link id="account-link" href="/account"> {WeftDom.Jsx.string(`Hi, ${name}`)} </Link>
        <button
          id="sign-out"
          onClick={_ =>
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
        </button>
      </>
    | None =>
      <button id="sign-in" onClick={_ => Store.openSignIn()}>
        {WeftDom.Jsx.string("Sign in")}
      </button>
    }}
  </div>
}
