/***
Progress through steps (a checkout, an order's delivery): each step done, the current one, or still
to come. The current step has `aria-current="step"`, and a finished one says so to assistive
technology.

```rescript
<Steps.Root ariaLabel="Checkout">
  <Steps.Step status=#complete> {text("Address")} </Steps.Step>
  <Steps.Step status=#current> {text("Delivery")} </Steps.Step>
  <Steps.Step status=#upcoming> {text("Review")} </Steps.Step>
</Steps.Root>
```

Static: a server component can render it.
*/
open WeftCss
module Jsx = WeftDom.Jsx

module Styles = {
  let layer = Tokens.layer
  let list = Css.class(
    ~layer,
    {
      display: Flex,
      flexWrap: Wrap,
      gap: Pair(Var(Tokens.spaceSm), Var(Tokens.spaceLg)),
      margin: Zero,
      padding: Zero,
      listStyle: None,
      fontSize: Var(Tokens.textSm),
      counterReset: "weft-step",
    },
  )
  let vertical = Css.class(~layer, {flexDirection: Column})
  /** Each step's number, or a tick once it's done. */
  let step = Css.class(
    ~layer,
    {
      display: InlineFlex,
      alignItems: Center,
      gap: Var(Tokens.spaceSm),
      color: Var(Tokens.fgMuted),
      counterIncrement: "weft-step",
      before: Css.style({
        content: "counter(weft-step) / \"\"",
        display: InlineFlex,
        alignItems: Center,
        justifyContent: Center,
        inlineSize: Raw("1.75em"),
        blockSize: Raw("1.75em"),
        borderRadius: Var(Tokens.radiusFull),
        border: `1px solid ${Tokens.value(Tokens.borderStrong)}`,
        fontSize: Var(Tokens.textXs),
        fontVariantNumeric: TabularNums,
      }),
    },
  )
  let complete = Css.class(
    ~layer,
    {
      color: Var(Tokens.fg),
      before: Css.style({
        content: "\"✓\" / \"\"",
        color: Var(Tokens.accentFg),
        backgroundColor: Var(Tokens.accent),
        borderColor: Var(Tokens.accent),
      }),
    },
  )
  let current = Css.class(
    ~layer,
    {
      color: Var(Tokens.fg),
      fontWeight: 600,
      before: Css.style({borderColor: Var(Tokens.accent), color: Var(Tokens.accent)}),
    },
  )
}

module Root = {
  @weft.component
  let make = (
    ~orientation: Variants.orientation=#horizontal,
    ~ariaLabel=?,
    ~id=?,
    ~className=?,
    ~style=?,
    ~dataId=?,
    ~children=?,
  ) =>
    <ol
      ?id
      className={Host.classes(
        orientation == #vertical ? [Styles.list, Styles.vertical] : [Styles.list],
        className,
      )}
      ?ariaLabel
      ?style
      ?dataId
      dataOrientation={Variants.orientationName(orientation)}
      ?children
    />
}

type status = [#complete | #current | #upcoming]

module Step = {
  @weft.component
  let make = (~status: status, ~id=?, ~className=?, ~dataId=?, ~children=?) =>
    <li
      ?id
      className={Host.classes(
        switch status {
        | #complete => [Styles.step, Styles.complete]
        | #current => [Styles.step, Styles.current]
        | #upcoming => [Styles.step]
        },
        className,
      )}
      ariaCurrent=?{status == #current ? Some("step") : None}
      dataState={(status :> string)}
      ?dataId
    >
      <span>
        {switch children {
        | Some(children) => children
        | None => Jsx.null
        }}
        {status == #complete
          ? <VisuallyHidden> {Jsx.string(" (done)")} </VisuallyHidden>
          : Jsx.null}
      </span>
    </li>
}
