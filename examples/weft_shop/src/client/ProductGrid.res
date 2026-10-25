/***
A grid of product cards, rendered on the server and given as data (`items`, each a card element and
the name to filter it by), with:

- a quick filter over the cards already here, following a deferred copy of what's typed
  (`useDeferredValue`), so typing stays quick while the grid renders;
- "Load more": the next page from the `catalog.more` RPC, whose answer is the cards themselves,
  rendered on the server (each still streaming its stock), added after these.

The server keys the grid by its filters, so changing them (a navigation) starts a fresh grid, while a
refresh with the same filters keeps the pages loaded.
*/

open Types

open WeftCss

module Styles = {
  let tools = Css.class({
    display: Flex,
    justifyContent: SpaceBetween,
    alignItems: Center,
    gap: Px(12),
  })
  let grid = Css.class({
    display: Grid,
    gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))",
    gap: Px(16),
    padding: Zero,
    listStyle: None,
    transition: "opacity .2s",
  })
  let loadMore = Css.class({marginTop: Px(16)})
}

@weft.component({kind: Entrypoint})
let make = (
  ~items: array<gridItem>,
  ~total: int,
  ~next as serverNext: option<int>,
  ~category: string,
  ~query: string,
) => {
  let (more, setMore) = Weft.Hooks.useState(() => [])
  let (next, setNext) = Weft.Hooks.useState(() => serverNext)
  let (loading, setLoading) = Weft.Hooks.useState(() => false)
  let (filter, setFilter) = Weft.Hooks.useState(() => "")
  let deferred = Weft.Hooks.useDeferredValue(filter)
  let loadMore = WeftServer.Rpc.use(Api.more)
  let all = [...items, ...more]
  let needle = deferred->String.trim->String.toLowerCase
  let shown =
    needle == ""
      ? all
      : all->Array.filter(item => item.name->String.toLowerCase->String.includes(needle))
  <div id="grid-wrap">
    <div className={Styles.tools}>
      <input
        id="quick-filter"
        type_="search"
        ariaLabel="Filter these results"
        placeholder="Filter these results"
        value=filter
        onInput={event => setFilter(_ => WeftDom.Dom.Event.targetValue(event))}
      />
      <p id="result-count">
        {WeftDom.Jsx.string(
          `Showing ${Int.toString(Array.length(shown))} of ${Int.toString(total)}`,
        )}
      </p>
    </div>
    <ul id="grid" className={filter == deferred ? Styles.grid : Css.cx([Styles.grid, Theme.stale])}>
      {shown
      ->Array.map(item => <li key=item.key> {item.card} </li>)
      ->WeftDom.Jsx.array}
    </ul>
    {shown == []
      ? <p id="no-results"> {WeftDom.Jsx.string("Nothing matches.")} </p>
      : WeftDom.Jsx.null}
    {switch next {
    | Some(page) =>
      <button
        id="load-more"
        className=Styles.loadMore
        disabled=loading
        onClick={_ => {
          setLoading(_ => true)

          (
            async () => {
              switch await loadMore({category, query, page}) {
              | Ok({items, next}) =>
                setMore(more => [...more, ...items])
                setNext(_ => next)
              | Error(error) => Store.toast(Api.describe(error))
              }
              setLoading(_ => false)
            }
          )()->ignore
        }}
      >
        {WeftDom.Jsx.string(loading ? "Loading…" : "Load more")}
      </button>
    | None => WeftDom.Jsx.null
    }}
  </div>
}
