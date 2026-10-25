/*** The toasts (`Store.toasts`), each dismissed after a few seconds, or by its button. */

open WeftCss

module Styles = {
  let toasts = Css.class({
    position: Fixed,
    right: Px(16),
    bottom: Px(16),
    display: Grid,
    gap: Px(8),
    margin: Zero,
    padding: Zero,
    listStyle: None,
  })
  let toast = Css.class({
    display: Flex,
    gap: Px(10),
    alignItems: Center,
    padding: Pair(Px(10), Px(14)),
    borderRadius: Px(8),
    backgroundColor: Var(Theme.ink),
    color: Named("white"),
  })
  let dismiss = Css.class({background: "none", color: Named("white"), border: "none"})
}

module Toast = {
  @weft.component
  let make = (~toast: Store.toast) => {
    Weft.Hooks.useEffect1(() => {
      let timer = setTimeout(() => Store.dismiss(toast.id), 4000)
      Some(() => clearTimeout(timer))
    }, [toast.id])
    <li className={Css.cx(["toast", Styles.toast])}>
      {WeftDom.Jsx.string(toast.text)}
      <button
        className={Css.cx(["toast-dismiss", Styles.dismiss])}
        ariaLabel="Dismiss"
        onClick={_ => Store.dismiss(toast.id)}
      >
        {WeftDom.Jsx.string("×")}
      </button>
    </li>
  }
}

@weft.component
let make = () => {
  let toasts = WeftSignals.SignalHooks.useSignal(Signals.Atom.toSignal(Store.toasts))
  <ul id="toasts" className=Styles.toasts role="status" ariaLive="polite">
    {toasts->Array.map(toast => <Toast key={Int.toString(toast.id)} toast />)->WeftDom.Jsx.array}
  </ul>
}
