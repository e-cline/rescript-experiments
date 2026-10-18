/***
Weft's public API: `weft_core` (components, hooks, the reconciler) and `weft_dom` (the DOM renderer)
behind one module.

Every entry is a module alias or a type alias, so `Weft.Hooks.useState` compiles to exactly what
`WeftCore.Hooks.useState` does: this package adds no code to a bundle, and a bundler still drops
whatever an app doesn't use. What it leaves out is the machinery for writing a renderer or testing
one (`Reconciler`, `Scheduler`, `HostConfig`, `JsxCore`, `TestRenderer`, ...), which stays in
`@e-cline/weft_core`.

```rescript
@@jsxConfig({version: 4, module_: "Weft.Jsx"})

module Counter = {
  @jsx.component
  let make = () => {
    let (count, setCount) = Weft.Hooks.useState(() => 0)
    <button onClick={_ => setCount(c => c + 1)}> {Weft.Jsx.int(count)} </button>
  }
}

switch Weft.Dom.document->Weft.Dom.body->Weft.Dom.querySelector("#app")->Nullable.toOption {
| Some(container) => Weft.Client.createRoot(container)->Weft.Client.render(<Counter />)
| None => ()
}
```
*/

/** What a component returns, and what `Client.render` takes. */
type element = WeftCore.Element.t

/** Hooks: `useState`, `useReducer`, `useEffect`, `useMemo`, `useContext`, ... */
module Hooks = WeftCore.Hooks

/** `Ref.t`, the mutable box `Hooks.useRef` returns. */
module Ref = WeftCore.Ref

/** Context: `Context.make` and `Context.provider`. */
module Context = WeftCore.Context

/** `Memo.memo`: skip re-rendering a component whose props are unchanged. */
module Memo = WeftCore.Memo

/** `Transition.start`: mark updates as non-urgent. */
module Transition = WeftCore.Transition

/** `<ErrorBoundary fallback>`: catch errors thrown while rendering below it. */
module ErrorBoundary = WeftCore.ErrorBoundary

/** `<Suspense fallback>`: show a fallback while a child waits on a promise (`Hooks.use`). */
module Suspense = WeftCore.Suspense

/**
The JSX module: `@@jsxConfig({version: 4, module_: "Weft.Jsx"})`. Host tags (`<div>`) take DOM
props. Components that should work under any renderer are written against `WeftCore.Jsx` instead.
*/
module Jsx = WeftDom.Jsx

/** `<Portal container> ... </Portal>`: render children into another DOM element. */
module Portal = WeftDom.Portal

/** `createRoot`, `render`, `unmount`, `flushSync`, and `act` for tests. */
module Client = WeftDom.Client

/** The small set of DOM bindings the renderer and components need. */
module Dom = WeftDom.Dom
