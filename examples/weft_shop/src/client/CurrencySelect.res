/***
Picks the currency prices are shown in: at once, for every price on the page (through
`ShopContext`), and for the session, so the server renders the next pages in it (the
`prefs.setCurrency` RPC). If saving fails, it goes back, and says so.
*/

module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = () => {
  let {currency, setCurrency} = ShopContext.use()
  let save = WeftServer.Rpc.use(Api.setCurrency)
  <WeftUi.Field label="Currency" hideLabel=true>
    <WeftUi.Select
      size=#sm
      dataId="currency"
      value={Money.code(currency)}
      onChange={event =>
        switch Money.fromCode(WeftDom.Dom.Event.targetValue(event)) {
        | Some(next) =>
          let previous = currency
          setCurrency(next)

          (
            async () =>
              switch await save(next) {
              | Ok() => ()
              | Error(error) =>
                setCurrency(previous)
                Store.toast(Api.describe(error))
              }
          )()->ignore
        | None => ()
        }}
    >
      {Money.currencies
      ->Array.map(option =>
        <WeftUi.Select.Option key={Money.code(option)} value={Money.code(option)}>
          {Jsx.string(`${Money.symbol(option)} ${Money.code(option)}`)}
        </WeftUi.Select.Option>
      )
      ->Jsx.array}
    </WeftUi.Select>
  </WeftUi.Field>
}
