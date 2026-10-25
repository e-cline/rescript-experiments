/*** Who's signed in, and signing in (the dialog) or out (the `auth.signOut` RPC, then a refresh). */

open WeftCss

module Styles = {
  let menu = Css.class({display: Flex, gap: Px(8), alignItems: Center})
}

@weft.component({kind: Entrypoint})
let make = () => {
  let {user} = ShopContext.use()
  let navigation = WeftServer.Navigation.useNavigation()
  let signOut = WeftServer.Rpc.use(Api.signOut)
  <div dataId="account-menu" className=Styles.menu>
    {switch user {
    | Some(name) =>
      <>
        <Link dataId="account-link" href="/account"> {WeftDom.Jsx.string(`Hi, ${name}`)} </Link>
        <button
          dataId="sign-out"
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
      <button dataId="sign-in" onClick={_ => Store.openSignIn()}>
        {WeftDom.Jsx.string("Sign in")}
      </button>
    }}
  </div>
}
