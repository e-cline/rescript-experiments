/*** Signing up for the newsletter (the `newsletter.subscribe` RPC, which checks the address on both sides). */

module Ui = WeftUi

@weft.component({kind: Entrypoint})
let make = () => {
  let (email, setEmail) = Weft.Hooks.useState(() => "")
  let (status, setStatus) = Weft.Hooks.useState(() => #idle)
  let subscribe = WeftServer.Rpc.use(Api.subscribe)
  switch status {
  | #done =>
    <Ui.Alert.Root tone=#success dataId="newsletter-done">
      <Ui.Alert.Description>
        {WeftDom.Jsx.string("Thanks: check your inbox.")}
      </Ui.Alert.Description>
    </Ui.Alert.Root>
  | #idle | #sending | #error(_) =>
    <Ui.Form
      dataId="newsletter"
      busy={status == #sending}
      onSubmit={() => {
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
      <Ui.Field
        label="Get the newsletter"
        error=?{switch status {
        | #error(message) => Some(message)
        | _ => None
        }}
      >
        <Ui.Stack direction=#row gap=#sm>
          <Ui.Input
            type_=#email
            inputMode="email"
            autoComplete="email"
            placeholder="you@example.com"
            value=email
            onInput={event => setEmail(_ => WeftDom.Dom.Event.targetValue(event))}
          />
          <Ui.Button
            dataId="newsletter-submit" type_=#submit variant=#primary busy={status == #sending}
          >
            {WeftDom.Jsx.string("Subscribe")}
          </Ui.Button>
        </Ui.Stack>
      </Ui.Field>
    </Ui.Form>
  }
}
