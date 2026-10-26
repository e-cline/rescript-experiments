/***
A category's filters and sort order, as the server decided to show them (`facets`: choices, a price
range, a toggle, whichever the category has). Each change makes the page's new URL and navigates to
it: the server renders the results for it, and the grid and the filters are replaced once they're
ready (a navigation renders in a transition). Meanwhile, the filters show what was just picked (the
query it's navigating to), not the server's, which would put a ticked box back until then.
*/

open Types

type params
@new external makeParams: string => params = "URLSearchParams"
@send external getAll: (params, string) => array<string> = "getAll"
@return(nullable) @send external getParam: (params, string) => option<string> = "get"
@send external setParam: (params, string, string) => unit = "set"
@send external appendParam: (params, string, string) => unit = "append"
@send external deleteParam: (params, string) => unit = "delete"
@send external paramsToString: params => string = "toString"

/** `query` changed by `change`, without the page number (a new filter starts at the first page). */
let changed = (query, change) => {
  let params = makeParams(query)
  change(params)
  params->deleteParam("page")
  params->paramsToString
}

module Ui = WeftUi

module RangeFacet = {
  @weft.component
  let make = (~name, ~label, ~min, ~max, ~low, ~high, ~apply: (int, int) => unit) => {
    let (from, setFrom) = Weft.Hooks.useState(() => Int.toString(low))
    let (to, setTo) = Weft.Hooks.useState(() => Int.toString(high))
    <Ui.Fieldset legend=label gap=#sm dataId={`facet-${name}`}>
      <Ui.Grid columns=2 gap=#sm>
        <Ui.Field label="From">
          <Ui.Input
            type_=#number
            size=#sm
            dataId={`${name}-from`}
            min={Int.toString(min)}
            max={Int.toString(max)}
            value=from
            onInput={event => setFrom(_ => WeftDom.Dom.Event.targetValue(event))}
          />
        </Ui.Field>
        <Ui.Field label="To">
          <Ui.Input
            type_=#number
            size=#sm
            dataId={`${name}-to`}
            min={Int.toString(min)}
            max={Int.toString(max)}
            value=to
            onInput={event => setTo(_ => WeftDom.Dom.Event.targetValue(event))}
          />
        </Ui.Field>
      </Ui.Grid>
      <div>
        <Ui.Button
          size=#sm
          dataId={`apply-${name}`}
          onClick={_ =>
            apply(Int.fromString(from)->Option.getOr(min), Int.fromString(to)->Option.getOr(max))}
        >
          {WeftDom.Jsx.string("Apply")}
        </Ui.Button>
      </div>
    </Ui.Fieldset>
  }
}

@weft.component({kind: Entrypoint})
let make = (
  ~basePath: string,
  ~query as serverQuery: string,
  ~facets: array<facet>,
  ~sort: string,
) => {
  let navigation = WeftServer.Navigation.useNavigation()
  // The query being navigated to, until its page has rendered.
  let (picked, setPicked) = Weft.Hooks.useState(() => None)
  let pending = picked->Option.isSome
  let query = picked->Option.getOr(serverQuery)
  let params = makeParams(query)
  let go = next => {
    setPicked(_ => Some(next))

    (
      async () => {
        // Resolves once the new page is on screen (or a newer navigation replaced it).
        await navigation->WeftServer.Navigation.navigate(
          next == "" ? basePath : `${basePath}?${next}`,
        )
        setPicked(current => current == Some(next) ? None : current)
      }
    )()->ignore
  }
  let sort = pending ? params->getParam("sort")->Option.getOr("featured") : sort
  <Ui.Stack
    as_=#aside
    gap=#lg
    dataId="facets"
    ariaLabel="Filters"
    className={pending ? Theme.stale : ""}
    attrs={{ariaBusy: pending ? "true" : "false"}}
  >
    <Ui.Field label="Sort by">
      <Ui.Select
        dataId="sort"
        value=sort
        onChange={event => {
          let value = WeftDom.Dom.Event.targetValue(event)
          go(changed(query, params => params->setParam("sort", value)))
        }}
      >
        {[
          ("featured", "Featured"),
          ("price-asc", "Price: low to high"),
          ("price-desc", "Price: high to low"),
          ("rating", "Rating"),
        ]
        ->Array.map(((value, label)) =>
          <Ui.Select.Option key=value value> {WeftDom.Jsx.string(label)} </Ui.Select.Option>
        )
        ->WeftDom.Jsx.array}
      </Ui.Select>
    </Ui.Field>
    {facets
    ->Array.map(facet =>
      switch facet {
      | Choices({name, label, options, selected}) =>
        let selected = pending ? params->getAll(name) : selected
        <Ui.Fieldset key=name legend=label gap=#sm dataId={`facet-${name}`}>
          {options
          ->Array.map(((value, count)) =>
            <Ui.Checkbox
              key=value
              dataId={`${name}-${value}`}
              checked={selected->Array.includes(value)}
              onCheckedChange={_ =>
                go(
                  changed(
                    query,
                    params => {
                      let current = params->getAll(name)
                      params->deleteParam(name)
                      let next =
                        current->Array.includes(value)
                          ? current->Array.filter(other => other != value)
                          : [...current, value]
                      next->Array.forEach(value => params->appendParam(name, value))
                    },
                  ),
                )}
            >
              {WeftDom.Jsx.string(`${value} (${Int.toString(count)})`)}
            </Ui.Checkbox>
          )
          ->WeftDom.Jsx.array}
        </Ui.Fieldset>
      | Range({name, label, min, max, low, high}) =>
        let picked = (param, fallback) =>
          params
          ->getParam(param)
          ->Option.flatMap(value => Int.fromString(value))
          ->Option.getOr(fallback)
        let (low, high) = pending ? (picked("min", min), picked("max", max)) : (low, high)
        // Keyed by the server's range, so new filters (cleared, say) reset what's typed.
        <RangeFacet
          key={`${name}-${Int.toString(low)}-${Int.toString(high)}`}
          name
          label
          min
          max
          low
          high
          apply={(low, high) =>
            go(
              changed(query, params => {
                params->setParam("min", Int.toString(low))
                params->setParam("max", Int.toString(high))
              }),
            )}
        />
      | Toggle({name, label, on}) =>
        let on = pending ? params->getParam(name) == Some("1") : on
        <Ui.Switch
          key=name
          dataId={`toggle-${name}`}
          checked=on
          onCheckedChange={_ =>
            go(
              changed(query, params =>
                on ? params->deleteParam(name) : params->setParam(name, "1")
              ),
            )}
        >
          {WeftDom.Jsx.string(label)}
        </Ui.Switch>
      }
    )
    ->WeftDom.Jsx.array}
    {query == ""
      ? WeftDom.Jsx.null
      : <div>
          <Ui.Button variant=#ghost size=#sm dataId="clear-filters" onClick={_ => go("")}>
            {WeftDom.Jsx.string("Clear all")}
          </Ui.Button>
        </div>}
  </Ui.Stack>
}
