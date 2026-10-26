/***
Signing in (the `auth.signIn` RPC): a name, and no password (it's a demo). Used by the dialog and by
the sign-in page. What's wrong with the name (empty, too long) is the field's error, linked to its
input.
*/

module Ui = WeftUi

@weft.component
let make = (~onSignedIn: string => unit, ~autoFocus=false) => {
  let (name, setName) = Weft.Hooks.useState(() => "")
  let (error, setError) = Weft.Hooks.useState(() => None)
  let (busy, setBusy) = Weft.Hooks.useState(() => false)
  let signIn = WeftServer.Rpc.use(Api.signIn)
  let submit = () => {
    setBusy(_ => true)

    (
      async () => {
        let result = await signIn(name)
        setBusy(_ => false)
        switch result {
        | Ok(name) =>
          setError(_ => None)
          onSignedIn(name)
        | Error(error) => setError(_ => Some(Api.describe(error)))
        }
      }
    )()->ignore
  }
  <Ui.Form onSubmit=submit busy>
    <Ui.Field label="Your name" ?error>
      <Ui.Input
        value=name
        autoFocus
        autoComplete="name"
        onInput={event => setName(_ => WeftDom.Dom.Event.targetValue(event))}
      />
    </Ui.Field>
    <Ui.Button type_=#submit variant=#primary busy>
      {WeftDom.Jsx.string(busy ? "Signing in…" : "Sign in")}
    </Ui.Button>
  </Ui.Form>
}
