/***
Picks the currency prices are shown in: at once, for every price on the page (through
`ShopContext`), and for the session, so the server renders the next pages in it (the
`prefs.setCurrency` RPC). If saving fails, it goes back, and says so.
*/

open WeftCss

@weft.component({kind: Entrypoint})
let make = () => {
  let {currency, setCurrency} = ShopContext.use()
  let save = WeftServer.Rpc.use(Api.setCurrency)
  <label className="currency">
    <span className={Css.cx(["visually-hidden", Theme.visuallyHidden])}>
      {WeftDom.Jsx.string("Currency")}
    </span>
    <select
      id="currency"
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
        <option key={Money.code(option)} value={Money.code(option)}>
          {WeftDom.Jsx.string(`${Money.symbol(option)} ${Money.code(option)}`)}
        </option>
      )
      ->WeftDom.Jsx.array}
    </select>
  </label>
}
