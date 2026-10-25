/***
An order's progress. While it's not delivered, it refreshes the page every `every` milliseconds (if
the server asks it to), so the server's newer status (and everything else on the page) comes in; a
refresh that fails is tried again next time.
*/

open Types

let steps = [Placed, Packed, Shipped, Delivered]

let rank = status =>
  switch status {
  | Placed => 0
  | Packed => 1
  | Shipped => 2
  | Delivered => 3
  }

open WeftCss

module Styles = {
  let timeline = Css.class({display: Flex, gap: Px(18), padding: Zero, listStyle: None})
  let done = Css.class({color: Hex("2f6b3a"), fontWeight: 600})
  let todo = Css.class({color: Var(Theme.muted)})
}

@weft.component({kind: Entrypoint})
let make = (~status: orderStatus, ~every: option<int>=?) => {
  let navigation = WeftServer.Navigation.useNavigation()
  Weft.Hooks.useEffect2(() =>
    switch (status, every) {
    | (Delivered, _) | (_, None) => None
    | (_, Some(every)) =>
      let timer = setInterval(
        () =>
          navigation->WeftServer.Navigation.refresh->Promise.catch(_ => Promise.resolve())->ignore,
        every,
      )
      Some(() => clearInterval(timer))
    }
  , (status, every))
  <ol id="timeline" className=Styles.timeline>
    {steps
    ->Array.map(step =>
      <li
        key={statusLabel(step)}
        className={rank(step) <= rank(status)
          ? Css.cx(["done", Styles.done])
          : Css.cx(["todo", Styles.todo])}
        ariaCurrent={step == status ? "step" : "false"}
      >
        {WeftDom.Jsx.string(statusLabel(step))}
      </li>
    )
    ->WeftDom.Jsx.array}
  </ol>
}
