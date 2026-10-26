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
  <WeftUi.Steps.Root ariaLabel="Delivery" dataId="timeline">
    {steps
    ->Array.map(step =>
      <WeftUi.Steps.Step
        key={statusLabel(step)}
        status={step == status && step != Delivered
          ? #current
          : rank(step) <= rank(status)
          ? #complete
          : #upcoming}
      >
        {WeftDom.Jsx.string(statusLabel(step))}
      </WeftUi.Steps.Step>
    )
    ->WeftDom.Jsx.array}
  </WeftUi.Steps.Root>
}
