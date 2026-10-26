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
module Ui = WeftUi

module Styles = {
  let search = Css.class({
    flex: "1",
    minWidth: Px(200),
    display: Flex,
    gap: Px(6),
    alignItems: Center,
  })
  let field = Css.class({flex: "1"})
}

module Suggestions = {
  /** The suggestions for `query` (the `search.suggest` RPC): a popup of them, while there are some. */
  @weft.component
  let make = (~query: string, ~onPick: unit => unit) => {
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
      : <Ui.Combobox.Popup ariaLabel="Suggestions">
          {suggestions
          ->Array.map(suggestion =>
            <Ui.Combobox.Item
              key=suggestion.slug
              value=suggestion.slug
              dataId={`suggestion-${suggestion.slug}`}
              onSelect={() => {
                onPick()
                navigation->WeftServer.Navigation.navigate(`/p/${suggestion.slug}`)->ignore
              }}
            >
              <span> {WeftDom.Jsx.string(suggestion.name)} </span>
              <Ui.Text as_=#span tone=#muted size=#xs>
                {WeftDom.Jsx.string(suggestion.category)}
              </Ui.Text>
            </Ui.Combobox.Item>
          )
          ->WeftDom.Jsx.array}
        </Ui.Combobox.Popup>
  }
}

@weft.component({kind: Entrypoint})
let make = (~initial: string) => {
  let (text, setText) = Weft.Hooks.useState(() => initial)
  let (showing, setShowing) = Weft.Hooks.useState(() => false)
  let deferred = Weft.Hooks.useDeferredValue(text)
  let navigation = WeftServer.Navigation.useNavigation()
  <form
    dataId="search"
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
    <Ui.Field label="Search" hideLabel=true className=Styles.field>
      <Ui.Combobox.Root>
        <Ui.Combobox.Input
          dataId="search-input"
          type_=#search
          size=#sm
          placeholder="Search the store"
          value=text
          onInput={event => {
            let value = WeftDom.Dom.Event.targetValue(event)
            setText(_ => value)
            setShowing(_ => true)
          }}
        />
        {showing
          ? <Suggestions query=deferred onPick={() => setShowing(_ => false)} />
          : WeftDom.Jsx.null}
      </Ui.Combobox.Root>
    </Ui.Field>
    <Ui.Button dataId="search-submit" type_=#submit size=#sm>
      {WeftDom.Jsx.string("Search")}
    </Ui.Button>
  </form>
}
