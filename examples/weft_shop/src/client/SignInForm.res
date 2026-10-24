/*** The sign-in page's form: once signed in, on to the page that asked for it (`next`). */

@weft.component({kind: Entrypoint})
let make = (~next: string) => {
  let navigation = WeftServer.Navigation.useNavigation()
  <div id="signin-page">
    <SignInFields
      onSignedIn={name => {
        Store.toast(`Signed in as ${name}`)
        navigation->WeftServer.Navigation.navigate(next)->ignore
      }}
    />
  </div>
}
