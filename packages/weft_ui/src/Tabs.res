/***
Tabs: a list of tabs, each showing its panel. The ARIA tabs pattern: the tab list is one Tab stop
(the selected tab), the arrow keys along its orientation move between tabs and select them as they
go (or, with `activation=#manual`, only on Enter or Space), and Home and End go to the ends.

```rescript
<Tabs.Root defaultValue="details">
  <Tabs.List label="Product">
    <Tabs.Tab value="details"> {text("Details")} </Tabs.Tab>
    <Tabs.Tab value="reviews"> {text("Reviews")} </Tabs.Tab>
  </Tabs.List>
  <Tabs.Panel value="details"> ... </Tabs.Panel>
  <Tabs.Panel value="reviews"> ... </Tabs.Panel>
</Tabs.Root>
```

Every panel stays mounted (`hidden` but for the selected one), so switching shows one that's already
there, and a panel's own state survives switching away and back; `keepMounted=false` renders only
the selected one. Without `value`, the selection is its own, from `defaultValue` (or, without one,
the first tab, once it has hydrated: give a `defaultValue` for the server's HTML to show a panel).

Interactive: it keeps state, so it renders inside an entrypoint (`TabsEntry` is one ready-made).
*/
open WeftCss
module Jsx = WeftDom.Jsx

module Dom = WeftDom.Dom

module Styles = {
  let layer = Tokens.layer
  let root = Css.class(~layer, {display: Flex, flexDirection: Column, gap: Var(Tokens.spaceMd)})
  let vertical = Css.class(~layer, {flexDirection: Row, alignItems: FlexStart})
  let list = Css.class(~layer, {display: Flex, gap: Var(Tokens.spaceXs), flexWrap: Wrap})
  let listVertical = Css.class(~layer, {flexDirection: Column, flexWrap: Nowrap})
  let underlineList = Css.class(~layer, {borderBottom: `1px solid ${Tokens.value(Tokens.border)}`})
  let underlineListVertical = Css.class(
    ~layer,
    {borderBottom: "none", borderInlineEnd: `1px solid ${Tokens.value(Tokens.border)}`},
  )
  let tab = Css.class(
    ~layer,
    {
      display: InlineFlex,
      alignItems: Center,
      gap: Var(Tokens.spaceXs),
      padding: Pair(Px(6), Var(Tokens.spaceMd)),
      border: "none",
      font: "inherit",
      fontSize: Var(Tokens.textSm),
      fontWeight: 500,
      color: Var(Tokens.fgMuted),
      backgroundColor: Transparent,
      cursor: Pointer,
      whiteSpace: Nowrap,
      focusVisible: Tokens.focusVisible(),
      hover: Css.style({color: Var(Tokens.fg)}),
      disabled: Css.style({opacity: 0.5, cursor: NotAllowed}),
    },
  )
  let underline = Css.class(
    ~layer,
    {
      marginBlockEnd: Px(-1),
      borderBottom: "2px solid transparent",
      selectors: [
        (
          "&[aria-selected=\"true\"]",
          Css.style({
            color: Var(Tokens.fg),
            borderBottom: `2px solid ${Tokens.value(Tokens.accent)}`,
          }),
        ),
      ],
    },
  )
  let underlineVertical = Css.class(
    ~layer,
    {
      marginBlockEnd: Zero,
      marginInlineEnd: Px(-1),
      borderBottom: "none",
      borderInlineEnd: "2px solid transparent",
      selectors: [
        (
          "&[aria-selected=\"true\"]",
          Css.style({
            color: Var(Tokens.fg),
            borderInlineEnd: `2px solid ${Tokens.value(Tokens.accent)}`,
          }),
        ),
      ],
    },
  )
  let pills = Css.class(
    ~layer,
    {
      borderRadius: Var(Tokens.radiusMd),
      selectors: [
        (
          "&[aria-selected=\"true\"]",
          Css.style({color: Var(Tokens.accentSoftFg), backgroundColor: Var(Tokens.accentSoft)}),
        ),
      ],
    },
  )
  let panel = Css.class(~layer, {minWidth: Zero, focusVisible: Tokens.focusVisible()})
}

type variant = [#underline | #pills]
type activation = [#automatic | #manual]

type state = {
  value: option<string>,
  select: string => unit,
  id: string,
  orientation: Variants.orientation,
  variant: variant,
  activation: activation,
}

let context = Weft.Context.make({
  value: None,
  select: _ => (),
  id: "",
  orientation: #horizontal,
  variant: #underline,
  activation: #automatic,
})

module Provider = {
  let make = Weft.Context.provider(context)
}

/** A value as part of an `id`: anything but letters, digits, `-` and `_` as `_`. */
let idPart = value => value->String.replaceRegExp(/[^A-Za-z0-9_-]/g, "_")
let tabId = (state, value) => `${state.id}-tab-${idPart(value)}`
let panelId = (state, value) => `${state.id}-panel-${idPart(value)}`

module Root = {
  @weft.component
  let make = (
    ~value: option<string>=?,
    ~defaultValue: option<string>=?,
    ~onValueChange: option<string => unit>=?,
    ~orientation: Variants.orientation=#horizontal,
    ~variant: variant=#underline,
    ~activation: activation=#automatic,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=?,
  ) => {
    let generated = Weft.Hooks.useId()
    let (current, select) = Controllable.use(
      ~value=value->Option.map(value => Some(value)),
      ~defaultValue,
      ~onChange=onValueChange->Option.map(onValueChange =>
        value => value->Option.forEach(onValueChange)
      ),
    )
    let ref = Weft.Hooks.useRef(Nullable.null)
    // With nothing selected, the first tab, once it's here.
    Weft.Hooks.useLayoutEffect0(() => {
      if current->Option.isNone {
        ref.current
        ->Nullable.toOption
        ->Option.flatMap(root =>
          Dom.querySelector(root, "[role=tab]:not(:disabled)")->Nullable.toOption
        )
        ->Option.flatMap(tab => Dom.getAttribute(tab, "value")->Nullable.toOption)
        ->Option.forEach(first => select(Some(first)))
      }
      None
    })
    <Provider
      value={{
        value: current,
        select: value => current == Some(value) ? () : select(Some(value)),
        id: generated,
        orientation,
        variant,
        activation,
      }}
    >
      <div
        ref
        ?id
        className={Host.classes(
          orientation == #vertical ? [Styles.root, Styles.vertical] : [Styles.root],
          className,
        )}
        ?style
        ?dataId
        dataOrientation={Variants.orientationName(orientation)}
      >
        {children->Option.getOr(Jsx.null)}
      </div>
    </Provider>
  }
}

module List = {
  /** The tabs. `label` names them (`aria-label`), unless a heading does (`ariaLabelledby`). */
  @weft.component
  let make = (~label=?, ~ariaLabelledby=?, ~className=?, ~dataId=?, ~children=?) => {
    let state = Weft.Hooks.useContext(context)
    let vertical = state.orientation == #vertical
    <div
      role="tablist"
      ariaLabel=?label
      ?ariaLabelledby
      ariaOrientation={Variants.orientationName(state.orientation)}
      className={Host.classes(
        Array.concat(
          vertical ? [Styles.list, Styles.listVertical] : [Styles.list],
          state.variant == #underline
            ? vertical
                ? [Styles.underlineList, Styles.underlineListVertical]
                : [Styles.underlineList]
            : [],
        ),
        className,
      )}
      ?dataId
      ?children
    />
  }
}

module Tab = {
  @weft.component
  let make = (~value: string, ~disabled=false, ~className=?, ~dataId=?, ~children=?) => {
    let state = Weft.Hooks.useContext(context)
    let selected = state.value == Some(value)
    <button
      type_="button"
      role="tab"
      id={tabId(state, value)}
      value
      ariaSelected={Host.ariaBool(selected)}
      ariaControls={panelId(state, value)}
      tabIndex={selected ? 0 : -1}
      disabled
      className={Host.classes(
        [
          Styles.tab,
          switch (state.variant, state.orientation) {
          | (#underline, #horizontal) => Styles.underline
          | (#underline, #vertical) => Styles.underlineVertical
          | (#pills, _) => Styles.pills
          },
        ],
        className,
      )}
      ?dataId
      onClick={_ => state.select(value)}
      onKeyDown={event =>
        switch Roving.onKeyDown(
          event,
          ~group=Styles.list,
          ~item=Styles.tab,
          ~orientation=state.orientation,
        ) {
        | Some(tab) if state.activation == #automatic =>
          Dom.getAttribute(tab, "value")->Nullable.forEach(state.select)
        | _ => ()
        }}
      ?children
    />
  }
}

module Panel = {
  @weft.component
  let make = (~value: string, ~keepMounted=true, ~className=?, ~dataId=?, ~children=?) => {
    let state = Weft.Hooks.useContext(context)
    let selected = state.value == Some(value)
    !selected && !keepMounted
      ? Jsx.null
      : <div
          role="tabpanel"
          id={panelId(state, value)}
          ariaLabelledby={tabId(state, value)}
          tabIndex=0
          hidden={!selected}
          className={Host.classes([Styles.panel], className)}
          ?dataId
          ?children
        />
  }
}
