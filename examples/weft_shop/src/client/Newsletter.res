/*** Signing up for the newsletter (the `newsletter.subscribe` RPC, which checks the address on both sides). */

@weft.component({kind: Entrypoint})
let make = () => {
  let (email, setEmail) = Weft.Hooks.useState(() => "")
  let (status, setStatus) = Weft.Hooks.useState(() => #idle)
  let inputId = Weft.Hooks.useId()
  let subscribe = WeftServer.Rpc.use(Api.subscribe)
  switch status {
  | #done => <p id="newsletter-done"> {WeftDom.Jsx.string("Thanks: check your inbox.")} </p>
  | #idle | #sending | #error(_) =>
    <form
      id="newsletter"
      onSubmit={event => {
        WeftDom.Dom.Event.preventDefault(event)
        setStatus(_ => #sending)

        (
          async () =>
            switch await subscribe(email) {
            | Ok() => setStatus(_ => #done)
            | Error(error) => setStatus(_ => #error(Api.describe(error)))
            }
        )()->ignore
      }}
    >
      <label htmlFor=inputId> {WeftDom.Jsx.string("Get the newsletter")} </label>
      <input
        id=inputId
        type_="email"
        inputMode="email"
        autoComplete="email"
        value=email
        onInput={event => setEmail(_ => WeftDom.Dom.Event.targetValue(event))}
      />
      <button id="newsletter-submit" type_="submit" disabled={status == #sending}>
        {WeftDom.Jsx.string("Subscribe")}
      </button>
      {switch status {
      | #error(message) => <p id="newsletter-error" role="alert"> {WeftDom.Jsx.string(message)} </p>
      | _ => WeftDom.Jsx.null
      }}
    </form>
  }
}
