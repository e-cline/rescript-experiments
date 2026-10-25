/***
Tabs, whose panels the server rendered (and streams: each is a block, in its own boundary). Every
panel stays mounted, hidden but for the selected one, so switching shows one that's already there,
and a panel's own state (a carousel's page) survives switching away and back.
*/

open WeftCss

module Styles = {
  let tabs = Css.class({
    selectors: [
      ("[role=\"tablist\"]", Css.style({display: Flex, gap: Px(6), marginBottom: Px(10)})),
      (
        "[aria-selected=\"true\"]",
        Css.style({backgroundColor: Var(Theme.ink), color: Named("white")}),
      ),
    ],
  })
}

@weft.component({kind: Entrypoint})
let make = (~id: string, ~labels: array<string>, ~panels: array<Weft.Element.t>) => {
  let (selected, setSelected) = Weft.Hooks.useState(() => 0)
  let selected = Math.Int.min(selected, Array.length(labels) - 1)
  let tabId = index => `${id}-tab-${Int.toString(index)}`
  let panelId = index => `${id}-panel-${Int.toString(index)}`
  <div className={Styles.tabs} id>
    <div role="tablist">
      {labels
      ->Array.mapWithIndex((label, index) =>
        <button
          key=label
          id={tabId(index)}
          role="tab"
          ariaSelected={index == selected ? "true" : "false"}
          ariaControls={panelId(index)}
          onClick={_ => setSelected(_ => index)}
        >
          {WeftDom.Jsx.string(label)}
        </button>
      )
      ->WeftDom.Jsx.array}
    </div>
    {panels
    ->Array.mapWithIndex((panel, index) =>
      <div
        key={Int.toString(index)}
        id={panelId(index)}
        role="tabpanel"
        ariaLabelledby={tabId(index)}
        hidden={index != selected}
      >
        panel
      </div>
    )
    ->WeftDom.Jsx.array}
  </div>
}
