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
  let grid = Css.class({
    display: Grid,
    gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))",
    gap: Px(16),
    padding: Zero,
    listStyle: None,
    transition: "opacity .2s",
  })
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
  <WeftUi.Stack gap=#md dataId="grid-wrap">
    <WeftUi.Stack direction=#row justify=#between align=#center gap=#md wrap=true>
      <WeftUi.Field label="Filter these results" hideLabel=true>
        <WeftUi.Input
          dataId="quick-filter"
          type_=#search
          size=#sm
          placeholder="Filter these results"
          value=filter
          onInput={event => setFilter(_ => WeftDom.Dom.Event.targetValue(event))}
        />
      </WeftUi.Field>
      <WeftUi.Text tone=#muted size=#sm dataId="result-count" role="status">
        {WeftDom.Jsx.string(
          `Showing ${Int.toString(Array.length(shown))} of ${Int.toString(total)}`,
        )}
      </WeftUi.Text>
    </WeftUi.Stack>
    <ul
      dataId="grid"
      className={filter == deferred ? Styles.grid : Css.cx([Styles.grid, Theme.stale])}
    >
      {shown
      ->Array.map(item => <li key=item.key> {item.card} </li>)
      ->WeftDom.Jsx.array}
    </ul>
    {shown == []
      ? <WeftUi.EmptyState.Root bordered=true dataId="no-results">
          <WeftUi.EmptyState.Title>
            {WeftDom.Jsx.string("Nothing matches.")}
          </WeftUi.EmptyState.Title>
        </WeftUi.EmptyState.Root>
      : WeftDom.Jsx.null}
    {switch next {
    | Some(page) =>
      <div>
        <WeftUi.Button
          dataId="load-more"
          busy=loading
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
        </WeftUi.Button>
      </div>
    | None => WeftDom.Jsx.null
    }}
  </WeftUi.Stack>
}
