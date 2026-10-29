/***
A set of toggles, one of which (`#single`) or any of which (`#multiple`) is pressed: a product's
sizes, a text's alignment. The group is named (`label`), and the arrow keys move between its items
(Home and End to the ends); Space or Enter presses one.

```rescript
<ToggleGroup.Root label="Size" value=[size] onValueChange={values => setSize(values[0])}>
  <ToggleGroup.Item value="s"> {text("S")} </ToggleGroup.Item>
  <ToggleGroup.Item value="m"> {text("M")} </ToggleGroup.Item>
</ToggleGroup.Root>
```

In a `#single` group, pressing the pressed item leaves it pressed: there's always a choice once one
is made. The group is one stop for Tab: the pressed item, or the one last focused.

Interactive: it keeps state, so it renders inside an entrypoint.
*/
open WeftCss
module Jsx = WeftDom.Jsx

module Styles = {
  let layer = Tokens.layer
  let group = Css.class(~layer, {display: InlineFlex, flexWrap: Wrap, gap: Var(Tokens.spaceXs)})
  let vertical = Css.class(~layer, {flexDirection: Column, alignItems: Stretch})
  /** Each item: how the keyboard finds them (`Roving`). */
  let item = Css.class(~layer, {})
}

type group = {
  value: array<string>,
  toggle: string => unit,
  /** The item Tab lands on. */
  tabStop: option<string>,
  setFocused: string => unit,
  orientation: Variants.orientation,
  variant: Button.variant,
  size: Variants.size,
  disabled: bool,
}

let context = Weft.Context.make({
  value: [],
  toggle: _ => (),
  tabStop: None,
  setFocused: _ => (),
  orientation: #horizontal,
  variant: #secondary,
  size: #md,
  disabled: false,
})

module Provider = {
  let make = Weft.Context.provider(context)
}

module Root = {
  @weft.component
  let make = (
    ~label: string,
    ~type_: [#single | #multiple]=#single,
    ~value: option<array<string>>=?,
    ~defaultValue=[],
    ~onValueChange: option<array<string> => unit>=?,
    ~orientation: Variants.orientation=#horizontal,
    ~variant: Button.variant=#secondary,
    ~size: Variants.size=#md,
    ~disabled=false,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=?,
  ) => {
    let (current, set) = Controllable.use(~value, ~defaultValue, ~onChange=onValueChange)
    let (focused, setFocused) = Weft.Hooks.useState(() => None)
    let toggle = item =>
      switch type_ {
      | #single => current == [item] ? () : set([item])
      | #multiple =>
        set(
          current->Array.includes(item)
            ? current->Array.filter(other => other != item)
            : [...current, item],
        )
      }
    let tabStop = switch focused {
    | Some(focused) => Some(focused)
    | None => current->Array.get(0)
    }
    <Provider
      value={{
        value: current,
        toggle,
        tabStop,
        setFocused: item => setFocused(_ => Some(item)),
        orientation,
        variant,
        size,
        disabled,
      }}
    >
      <div
        ?id
        role="group"
        ariaLabel=label
        className={Host.classes(
          orientation == #vertical ? [Styles.group, Styles.vertical] : [Styles.group],
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

module Item = {
  @weft.component
  let make = (
    ~value: string,
    ~label: option<string>=?,
    ~disabled=false,
    ~className as extra=?,
    ~style=?,
    ~dataId=?,
    ~children=Jsx.null,
  ) => {
    let group = Weft.Hooks.useContext(context)
    let pressed = group.value->Array.includes(value)
    // One Tab stop: this item, if it's the group's; every item while there's none yet.
    let tabIndex = switch group.tabStop {
    | Some(stop) => stop == value ? 0 : -1
    | None => 0
    }
    Button.render(
      ~className=Host.classes(
        [
          Toggle.className(~variant=group.variant, ~size=group.size, ~icon=label->Option.isSome),
          Styles.item,
        ],
        extra,
      ),
      ~type_=#button,
      ~busy=false,
      ~disabled=disabled || group.disabled,
      ~onClick=Some(_ => group.toggle(value)),
      ~id=None,
      ~style,
      ~dataId,
      ~ariaLabel=label,
      ~ariaDescribedby=None,
      ~ariaExpanded=None,
      ~ariaControls=None,
      ~ariaHaspopup=None,
      ~ariaPressed=Some(Host.ariaBool(pressed)),
      ~name=None,
      ~value=Some(value),
      ~title=None,
      ~attrs={
        tabIndex,
        onFocus: _ => group.setFocused(value),
        onKeyDown: event =>
          Roving.onKeyDown(
            event,
            ~group=Styles.group,
            ~item=Styles.item,
            ~orientation=group.orientation,
          )->ignore,
      },
      ~children=switch label {
      | Some(_) => <span ariaHidden="true"> children </span>
      | None => children
      },
    )
  }
}
