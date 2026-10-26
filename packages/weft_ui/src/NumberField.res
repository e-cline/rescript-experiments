/***
A number, typed or stepped: a text input with `role="spinbutton"`, and buttons either side.

```rescript
<Field label="Quantity">
  <NumberField.Root value=quantity onValueChange=setQuantity min=1. max=10.>
    <NumberField.Decrement />
    <NumberField.Input />
    <NumberField.Increment />
  </NumberField.Root>
</Field>
```

- What's typed is a draft until it's committed (on blur, or Enter): then it's read as a number and
  kept within `min` and `max`, or, if it isn't one, put back as it was.
- ArrowUp and ArrowDown step by `step`, PageUp and PageDown by ten steps, and Home and End go to
  `min` and `max`.
- The buttons step too. They're out of the tab order (the arrow keys do what they do), and each
  is disabled at its end of the range.

Without `value`, it keeps its own (from `defaultValue`).

Interactive: it keeps state, so it renders inside an entrypoint.
*/
open WeftCss

module Styles = {
  let layer = Tokens.layer
  let group = Css.class(
    ~layer,
    {
      display: InlineFlex,
      alignItems: Stretch,
      maxWidth: Pct(100.),
      selectors: [
        // The parts join into one control: only the outer corners are round.
        (
          "& > :not(:first-child)",
          Css.style({borderStartStartRadius: Zero, borderEndStartRadius: Zero}),
        ),
        (
          "& > :not(:last-child)",
          Css.style({borderStartEndRadius: Zero, borderEndEndRadius: Zero}),
        ),
        ("& > * + *", Css.style({marginInlineStart: Px(-1)})),
      ],
    },
  )
  let input = Css.class(
    ~layer,
    {
      ...Controls.base(),
      inlineSize: Raw("7ch"),
      textAlign: Center,
      fontVariantNumeric: TabularNums,
      position: Relative,
      focusVisible: Css.style({
        outline: `2px solid ${Tokens.value(Tokens.focusRing)}`,
        outlineOffset: Zero,
        borderColor: Var(Tokens.focusRing),
        zIndex: 1,
      }),
    },
  )
  let sm = Css.class(~layer, Controls.sized(#sm))
  let md = Css.class(~layer, Controls.sized(#md))
  let lg = Css.class(~layer, Controls.sized(#lg))
  let button = Css.class(
    ~layer,
    {
      borderColor: Var(Tokens.borderStrong),
      fontSize: Var(Tokens.textMd),
      fontVariantNumeric: TabularNums,
    },
  )
}

type value = {
  value: float,
  min: float,
  max: float,
  step: float,
  size: Variants.size,
  disabled: bool,
  set: float => unit,
}

let context = Weft.Context.make({
  value: 0.,
  min: Float.Constants.negativeInfinity,
  max: Float.Constants.positiveInfinity,
  step: 1.,
  size: #md,
  disabled: false,
  set: _ => (),
})

module Provider = {
  let make = Weft.Context.provider(context)
}

let clamp = (value, ~min, ~max) => Math.max(min, Math.min(max, value))

/** A number as it's shown (JavaScript's way: no decimal point for a whole one). */
let format = Float.toString

module Root = {
  @weft.component
  let make = (
    ~value: option<float>=?,
    ~defaultValue=0.,
    ~onValueChange: option<float => unit>=?,
    ~min=Float.Constants.negativeInfinity,
    ~max=Float.Constants.positiveInfinity,
    ~step=1.,
    ~size: Variants.size=#md,
    ~disabled=false,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=?,
  ) => {
    let (current, set) = Controllable.use(~value, ~defaultValue, ~onChange=onValueChange)
    let set = next => {
      let next = clamp(next, ~min, ~max)
      if next != current {
        set(next)
      }
    }
    <Provider value={{value: current, min, max, step, size, disabled, set}}>
      <div ?id className={Host.classes([Styles.group], className)} ?style ?dataId>
        {children->Option.getOr(WeftDom.Jsx.null)}
      </div>
    </Provider>
  }
}

module Input = {
  @weft.component
  let make = (~name=?, ~ariaLabel=?, ~ariaDescribedby=?, ~id=?, ~className=?, ~dataId=?) => {
    let field = FieldContext.use()
    let number = Weft.Hooks.useContext(context)
    // What's typed, until it's committed.
    let (draft, setDraft) = Weft.Hooks.useState(() => None)
    let commit = () => {
      switch draft {
      | Some(text) =>
        switch Float.fromString(String.trim(text)) {
        | Some(typed) => number.set(typed)
        | None => ()
        }
      | None => ()
      }
      setDraft(_ => None)
    }
    let onKeyDown = event => {
      let by = steps => {
        WeftDom.Dom.Event.preventDefault(event)
        setDraft(_ => None)
        number.set(number.value +. steps *. number.step)
      }
      switch WeftDom.Dom.Event.key(event) {
      | "ArrowUp" => by(1.)
      | "ArrowDown" => by(-1.)
      | "PageUp" => by(10.)
      | "PageDown" => by(-10.)
      | "Home" if number.min != Float.Constants.negativeInfinity =>
        WeftDom.Dom.Event.preventDefault(event)
        number.set(number.min)
      | "End" if number.max != Float.Constants.positiveInfinity =>
        WeftDom.Dom.Event.preventDefault(event)
        number.set(number.max)
      | "Enter" => commit()
      | _ => ()
      }
    }
    let finite = bound => Float.isFinite(bound) ? Some(bound) : None
    <input
      type_="text"
      inputMode={Math.floor(number.step) == number.step && number.min >= 0. ? "numeric" : "decimal"}
      role="spinbutton"
      autoComplete="off"
      id=?{id->Option.orElse(field.controlId)}
      className={Host.classes(
        [
          Styles.input,
          switch number.size {
          | #sm => Styles.sm
          | #md => Styles.md
          | #lg => Styles.lg
          },
        ],
        className,
      )}
      ?dataId
      ?name
      value={draft->Option.getOr(format(number.value))}
      onInput={event => setDraft(_ => Some(WeftDom.Dom.Event.targetValue(event)))}
      onBlur={_ => commit()}
      onKeyDown
      disabled={number.disabled || field.disabled}
      ariaValuenow=number.value
      ariaValuemin=?{finite(number.min)}
      ariaValuemax=?{finite(number.max)}
      ariaInvalid=?{field.invalid ? Some("true") : None}
      ariaRequired=?{field.required ? Some("true") : None}
      ?ariaLabel
      ariaDescribedby=?{FieldContext.describedBy(ariaDescribedby, field.describedBy)}
    />
  }
}

/** A button that steps the number by `steps` (`-1.` for `Decrement`), disabled at its end. */
let stepper = (~steps: float, ~label: string, ~symbol: string, ~className, ~dataId) => {
  let number = Weft.Hooks.useContext(context)
  let atEnd = steps < 0. ? number.value <= number.min : number.value >= number.max
  <IconButton
    label
    variant=#secondary
    size=number.size
    disabled={number.disabled || atEnd}
    attrs={{tabIndex: -1}}
    className={Host.classes([Styles.button], className)}
    ?dataId
    onClick={_ => number.set(number.value +. steps *. number.step)}
  >
    {WeftDom.Jsx.string(symbol)}
  </IconButton>
}

module Decrement = {
  @weft.component
  let make = (~label="Decrease", ~className=?, ~dataId=?) =>
    stepper(~steps=-1., ~label, ~symbol="−", ~className, ~dataId)
}

module Increment = {
  @weft.component
  let make = (~label="Increase", ~className=?, ~dataId=?) =>
    stepper(~steps=1., ~label, ~symbol="+", ~className, ~dataId)
}
