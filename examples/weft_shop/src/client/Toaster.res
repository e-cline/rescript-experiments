/*** The toasts (`Store.toasts`), each dismissed after a few seconds, or by its button. */

module Toast = {
  @weft.component
  let make = (~toast: Store.toast) => {
    Weft.Hooks.useEffect1(() => {
      let timer = setTimeout(() => Store.dismiss(toast.id), 4000)
      Some(() => clearTimeout(timer))
    }, [toast.id])
    <li className="toast">
      {WeftDom.Jsx.string(toast.text)}
      <button className="toast-dismiss" ariaLabel="Dismiss" onClick={_ => Store.dismiss(toast.id)}>
        {WeftDom.Jsx.string("×")}
      </button>
    </li>
  }
}

@weft.component
let make = () => {
  let toasts = WeftSignals.SignalHooks.useSignal(Signals.Atom.toSignal(Store.toasts))
  <ul id="toasts" role="status" ariaLive="polite">
    {toasts->Array.map(toast => <Toast key={Int.toString(toast.id)} toast />)->WeftDom.Jsx.array}
  </ul>
}
