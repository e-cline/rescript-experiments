/***
The search box in the header: suggestions as you type (the `search.suggest` RPC), and the results
page on Enter. It's in the header, which every page has in the same place, so what's typed stays as
the shopper navigates.

The suggestions follow a deferred copy of the text (`useDeferredValue`), so typing stays quick while
they render, and each request cancels the one before it (an `AbortSignal` given to `Rpc.call`): a
slow answer to an older text can't replace a newer one's.
*/

type controller
@new external makeController: unit => controller = "AbortController"
@get external controllerSignal: controller => WeftServer.Rpc.signal = "signal"
@send external abort: controller => unit = "abort"

open WeftCss

module Styles = {
  let search = Css.class({
    position: Relative,
    flex: "1",
    minWidth: Px(200),
    display: Flex,
    gap: Px(6),
  })
  let input = Css.class({
    flex: "1",
    padding: Pair(Px(6), Px(10)),
    border: Theme.hairline(),
    borderRadius: Px(6),
  })
  let suggestions = Css.class({
    position: Absolute,
    top: Pct(100.),
    left: Zero,
    right: Zero,
    zIndex: 5,
    margin: Four(Px(4), Zero, Zero, Zero),
    padding: Px(4),
    listStyle: None,
    backgroundColor: Named("white"),
    border: Theme.hairline(),
    borderRadius: Px(6),
    selectors: [
      ("li", Css.style({display: Flex, justifyContent: SpaceBetween, padding: Pair(Px(4), Px(6))})),
    ],
  })
  let category = Css.class({color: Var(Theme.muted), fontSize: Px(13)})
}

module Suggestions = {
  @weft.component
  let make = (~query: string, ~listId: string, ~onPick: unit => unit) => {
    let navigation = WeftServer.Navigation.useNavigation()
    let (found, setFound) = Weft.Hooks.useState(() => (query, []))
    Weft.Hooks.useEffect1(() => {
      let query = String.trim(query)
      if String.length(query) < 2 {
        setFound(_ => (query, []))
        None
      } else {
        let controller = makeController()

        (
          async () =>
            switch await WeftServer.Rpc.call(
              Api.suggest,
              ~client=navigation->WeftServer.Navigation.client,
              query,
              ~signal=controller->controllerSignal,
            ) {
            | Ok(suggestions) => setFound(_ => (query, suggestions))
            // Cancelled by a newer query, or failed: nothing to show for this one.
            | Error(_) => ()
            }
        )()->ignore
        Some(() => controller->abort)
      }
    }, [query])
    let (forQuery, suggestions) = found
    suggestions == [] || forQuery != String.trim(query)
      ? WeftDom.Jsx.null
      : <ul id=listId className={Css.cx(["suggestions", Styles.suggestions])} role="listbox">
          {suggestions
          ->Array.map(suggestion =>
            <li key=suggestion.slug role="option" onClick={_ => onPick()}>
              <Link id={`suggestion-${suggestion.slug}`} href={`/p/${suggestion.slug}`}>
                {WeftDom.Jsx.string(suggestion.name)}
              </Link>
              <span className={Css.cx(["suggestion-category", Styles.category])}>
                {WeftDom.Jsx.string(suggestion.category)}
              </span>
            </li>
          )
          ->WeftDom.Jsx.array}
        </ul>
  }
}

@weft.component({kind: Entrypoint})
let make = (~initial: string) => {
  let (text, setText) = Weft.Hooks.useState(() => initial)
  let (showing, setShowing) = Weft.Hooks.useState(() => false)
  let deferred = Weft.Hooks.useDeferredValue(text)
  let navigation = WeftServer.Navigation.useNavigation()
  let listId = Weft.Hooks.useId()
  <form
    id="search"
    className=Styles.search
    role="search"
    onSubmit={event => {
      WeftDom.Dom.Event.preventDefault(event)
      setShowing(_ => false)
      navigation
      ->WeftServer.Navigation.navigate(`/search?q=${encodeURIComponent(String.trim(text))}`)
      ->ignore
    }}
  >
    <input
      id="search-input"
      className=Styles.input
      type_="search"
      ariaLabel="Search"
      placeholder="Search the store"
      autoComplete="off"
      role="combobox"
      ariaControls=listId
      ariaExpanded={showing ? "true" : "false"}
      value=text
      onInput={event => {
        let value = WeftDom.Dom.Event.targetValue(event)
        setText(_ => value)
        setShowing(_ => true)
      }}
    />
    <button id="search-submit" type_="submit"> {WeftDom.Jsx.string("Search")} </button>
    {showing
      ? <Suggestions query=deferred listId onPick={() => setShowing(_ => false)} />
      : WeftDom.Jsx.null}
  </form>
}
