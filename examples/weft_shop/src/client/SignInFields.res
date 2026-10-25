/***
Signing in (the `auth.signIn` RPC): a name, and no password (it's a demo). Used by the dialog and by
the sign-in page. Its label is linked by an ID from `useId`.
*/

open WeftCss

module Styles = {
  let form = Css.class({display: Grid, gap: Px(8)})
}

@weft.component
let make = (~onSignedIn: string => unit, ~autoFocus=false) => {
  let (name, setName) = Weft.Hooks.useState(() => "")
  let (error, setError) = Weft.Hooks.useState(() => None)
  let (busy, setBusy) = Weft.Hooks.useState(() => false)
  let inputId = Weft.Hooks.useId()
  let signIn = WeftServer.Rpc.use(Api.signIn)
  let submit = event => {
    WeftDom.Dom.Event.preventDefault(event)
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
  <form className={Css.cx(["signin-form", Styles.form])} onSubmit=submit>
    <label htmlFor=inputId> {WeftDom.Jsx.string("Your name")} </label>
    <input
      id=inputId
      className="signin-name"
      value=name
      autoFocus
      autoComplete="name"
      onInput={event => setName(_ => WeftDom.Dom.Event.targetValue(event))}
    />
    <button className="signin-submit" type_="submit" disabled=busy>
      {WeftDom.Jsx.string(busy ? "Signing in…" : "Sign in")}
    </button>
    {switch error {
    | Some(message) => <p className="signin-error" role="alert"> {WeftDom.Jsx.string(message)} </p>
    | None => WeftDom.Jsx.null
    }}
  </form>
}
