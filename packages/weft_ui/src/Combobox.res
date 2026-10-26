/***
A text input with suggestions: the ARIA editable combobox, its list a listbox in a popup under the
input. What's typed is the app's (the `Input`'s `value` and `onInput`), and so are the suggestions
(the `Item`s it renders: filtered here, or fetched as the text changes); the combobox does the rest.

```rescript
<Field label="Search" hideLabel=true>
  <Combobox.Root onSelect={slug => navigate(`/p/${slug}`)}>
    <Combobox.Input value=text onInput placeholder="Search the store" />
    {suggestions == []
      ? WeftDom.Jsx.null
      : <Combobox.Popup>
          {suggestions->Array.map(s => <Combobox.Item key=s.slug value=s.slug> ... </Combobox.Item>)}
        </Combobox.Popup>}
  </Combobox.Root>
</Field>
```

- **Typing** opens the popup (if the app renders one), with nothing highlighted.
- **ArrowDown and ArrowUp** highlight the next and previous suggestion (opening the popup first if
  it's closed), wrapping round. The focus stays in the input, and the highlighted suggestion is its
  `aria-activedescendant`, so assistive technology reads it.
- **Enter** chooses the highlighted suggestion (`onSelect`, the `Root`'s and the `Item`'s), and
  closes the popup. With nothing highlighted, Enter does what it would anyway (submits the form).
- **Escape, Tab, or leaving** the input closes it. The pointer highlights what it's over, and a
  click chooses it.

The input is an `Input`, so a `Field` around the root labels it. The popup is in the top layer,
under the input (CSS anchor positioning), and only open while the app renders it, so
`aria-expanded` says whether there are suggestions to see.

Interactive: it keeps state, so it renders inside an entrypoint.
*/
open WeftCss

module Dom = WeftDom.Dom

module Styles = {
  let layer = Tokens.layer
  let root = Css.class(
    ~layer,
    {position: Relative, display: Flex, flexDirection: Column, minWidth: Zero},
  )
  // Its layout only while it's open (see `Popover`'s panel).
  let popup = Css.class(
    ~layer,
    {
      selectors: [("&:popover-open", Css.style({display: Flex}))],
      flexDirection: Column,
      minInlineSize: Px(240),
      maxInlineSize: Raw("min(480px, 100vw - 16px)"),
      maxBlockSize: Px(320),
      overflowY: Auto,
      padding: Var(Tokens.spaceXs),
      fontSize: Var(Tokens.textSm),
      color: Var(Tokens.fg),
      backgroundColor: Var(Tokens.surface),
      border: `1px solid ${Tokens.value(Tokens.border)}`,
      borderRadius: Var(Tokens.radiusMd),
      boxShadow: Tokens.value(Tokens.shadowMd),
    },
  )
  let item = Css.class(
    ~layer,
    {
      display: Flex,
      alignItems: Center,
      justifyContent: SpaceBetween,
      gap: Var(Tokens.spaceSm),
      minHeight: Var(Tokens.controlSm),
      padding: Pair(Px(4), Var(Tokens.spaceSm)),
      borderRadius: Var(Tokens.radiusSm),
      cursor: Pointer,
      selectors: [
        ("&[data-highlighted]", Css.style({backgroundColor: Var(Tokens.surfaceMuted)})),
        ("&[aria-disabled=\"true\"]", Css.style({opacity: 0.5, cursor: Default})),
      ],
    },
  )
  let empty = Css.class(
    ~layer,
    {padding: Pair(Px(6), Var(Tokens.spaceSm)), color: Var(Tokens.fgMuted)},
  )
}

type state = {
  open_: bool,
  setOpen: bool => unit,
  /** Whether the app renders a popup now (the `Popup` says so as it mounts and unmounts). */
  hasPopup: bool,
  setHasPopup: bool => unit,
  highlighted: option<string>,
  setHighlighted: option<string> => unit,
  choose: (~value: string, ~onSelect: option<unit => unit>) => unit,
  listId: string,
  anchor: string,
  popup: Overlay.ref,
}

let context = Weft.Context.make({
  open_: false,
  setOpen: _ => (),
  hasPopup: false,
  setHasPopup: _ => (),
  highlighted: None,
  setHighlighted: _ => (),
  choose: (~value as _, ~onSelect as _) => (),
  listId: "",
  anchor: "",
  popup: {current: Nullable.null},
})

module Provider = {
  let make = Weft.Context.provider(context)
}

/** The popup's options that can be chosen, in order. */
let options = (state: state) =>
  state.popup.current
  ->Nullable.toOption
  ->Option.mapOr([], popup =>
    popup
    ->Dom.querySelectorAll("[role=option]")
    ->Array.filter(option => !Dom.matches(option, "[aria-disabled=\"true\"]"))
  )

module Root = {
  @weft.component
  let make = (
    ~onSelect: option<string => unit>=?,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=?,
  ) => {
    let generated = Weft.Hooks.useId()
    let (open_, setOpen) = Weft.Hooks.useState(() => false)
    let (hasPopup, setHasPopup) = Weft.Hooks.useState(() => false)
    let (highlighted, setHighlighted) = Weft.Hooks.useState(() => None)
    let popup = Weft.Hooks.useRef(Nullable.null)
    <Provider
      value={{
        open_,
        setOpen: next => {
          setOpen(_ => next)
          if !next {
            setHighlighted(_ => None)
          }
        },
        hasPopup,
        setHasPopup: has => setHasPopup(_ => has),
        highlighted,
        setHighlighted: next => setHighlighted(_ => next),
        choose: (~value, ~onSelect as itemSelect) => {
          itemSelect->Option.forEach(select => select())
          onSelect->Option.forEach(select => select(value))
          setOpen(_ => false)
          setHighlighted(_ => None)
        },
        listId: `${generated}-list`,
        anchor: Overlay.anchorName(generated),
        popup,
      }}
    >
      <div ?id className={Host.classes([Styles.root], className)} ?style ?dataId>
        {children->Option.getOr(WeftDom.Jsx.null)}
      </div>
    </Provider>
  }
}

module Input = {
  /** The text input: an `Input`, with the combobox's role, state and keyboard. */
  @weft.component
  let make = (
    ~value=?,
    ~onInput: option<Dom.event => unit>=?,
    ~onKeyDown: option<Dom.event => unit>=?,
    ~onBlur: option<Dom.event => unit>=?,
    ~type_: Input.type_=#text,
    ~size: Variants.size=#md,
    ~name=?,
    ~placeholder=?,
    ~ariaLabel=?,
    ~id=?,
    ~className=?,
    ~dataId=?,
  ) => {
    let state = Weft.Hooks.useContext(context)
    let expanded = state.open_ && state.hasPopup
    // The highlighted option, if it's still one of the popup's.
    let highlighted = switch state.highlighted {
    | Some(id)
      if options(state)->Array.some(option =>
        Dom.getAttribute(option, "id") == Nullable.make(id)
      ) =>
      Some(id)
    | _ => None
    }
    let move = (event, step) => {
      Dom.Event.preventDefault(event)
      if !state.open_ {
        state.setOpen(true)
      }
      let all = options(state)
      let count = Array.length(all)
      if count > 0 {
        let index =
          all->Array.findIndex(option =>
            Some(Dom.getAttribute(option, "id")->Nullable.toOption->Option.getOr("")) == highlighted
          )
        let next = if index < 0 {
          step > 0 ? 0 : count - 1
        } else {
          mod(index + step + count, count)
        }
        let option = all->Array.getUnsafe(next)
        Dom.scrollIntoView(option, {"block": "nearest"})
        state.setHighlighted(Dom.getAttribute(option, "id")->Nullable.toOption)
      }
    }
    <Input
      ?value
      type_
      size
      ?name
      ?placeholder
      ?ariaLabel
      ?id
      ?className
      ?dataId
      autoComplete="off"
      style={dict{"anchor-name": state.anchor}}
      attrs={{
        role: "combobox",
        ariaExpanded: Host.ariaBool(expanded),
        ariaControls: state.listId,
        ariaAutocomplete: "list",
        ariaActivedescendant: ?(expanded ? highlighted : None),
      }}
      onInput={event => {
        onInput->Option.forEach(onInput => onInput(event))
        state.setHighlighted(None)
        if !state.open_ {
          state.setOpen(true)
        }
      }}
      onKeyDown={event => {
        onKeyDown->Option.forEach(onKeyDown => onKeyDown(event))
        if !Dom.Event.defaultPrevented(event) {
          switch Dom.Event.key(event) {
          | "ArrowDown" => move(event, 1)
          | "ArrowUp" => move(event, -1)
          | "Enter" =>
            switch (expanded, highlighted) {
            | (true, Some(id)) =>
              Dom.Event.preventDefault(event)
              // The option's own click chooses it, with its `onSelect`.
              options(state)
              ->Array.find(option => Dom.getAttribute(option, "id") == Nullable.make(id))
              ->Option.forEach(Dom.click)
            | _ => ()
            }
          | "Escape" if state.open_ =>
            Dom.Event.preventDefault(event)
            state.setOpen(false)
          | "Tab" => state.setOpen(false)
          | _ => ()
          }
        }
      }}
      onBlur={event => {
        onBlur->Option.forEach(onBlur => onBlur(event))
        state.setOpen(false)
      }}
    />
  }
}

module Popup = {
  /** The suggestions: render it while there are some (or an `Empty` to say there aren't). */
  @weft.component
  let make = (~className=?, ~dataId=?, ~ariaLabel=?, ~children=?) => {
    let state = Weft.Hooks.useContext(context)
    let shown = Weft.Hooks.useRef(false)
    Weft.Hooks.useLayoutEffect0(() => {
      state.setHasPopup(true)
      Some(() => state.setHasPopup(false))
    })
    Anchored.usePopover(state.popup, ~shown, state.open_)
    <div
      ref=state.popup
      id=state.listId
      popover="manual"
      role="listbox"
      ?ariaLabel
      className={Host.classes([Anchored.Styles.anchored, Styles.popup], className)}
      style={Anchored.popupStyle(~anchor=state.anchor, ~side=#bottom, ~align=#start, None)}
      ?dataId
      // A press in it doesn't take the focus from the input (which would close it).
      onPointerDown={event => Dom.Event.preventDefault(event)}
      onMouseDown={event => Dom.Event.preventDefault(event)}
      ?children
    />
  }
}

module Item = {
  /** A suggestion: chosen by Enter while it's highlighted, or a click. */
  @weft.component
  let make = (
    ~value: string,
    ~onSelect: option<unit => unit>=?,
    ~disabled=false,
    ~className=?,
    ~dataId=?,
    ~children=?,
  ) => {
    let state = Weft.Hooks.useContext(context)
    let id = Weft.Hooks.useId()
    let highlighted = state.highlighted == Some(id)
    <div
      id
      role="option"
      ariaSelected={Host.ariaBool(highlighted)}
      ariaDisabled=?{disabled ? Some("true") : None}
      dataHighlighted=highlighted
      className={Host.classes([Styles.item], className)}
      ?dataId
      onPointerMove={_ =>
        if !disabled && !highlighted {
          state.setHighlighted(Some(id))
        }}
      onClick={_ =>
        if !disabled {
          state.choose(~value, ~onSelect)
        }}
      ?children
    />
  }
}

module Empty = {
  /** What the popup says when there's nothing to suggest. */
  @weft.component
  let make = (~className=?, ~dataId=?, ~children=?) =>
    <div
      className={Host.classes([Styles.empty], className)} ?dataId role="presentation" ?children
    />
}
