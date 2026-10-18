# @e-cline/weft

Weft is a React-like UI framework written in ReScript, with no React underneath. This is the package
to depend on: the public API of [`@e-cline/weft_core`](../weft_core) (components, hooks, the
reconciler) and [`@e-cline/weft_dom`](../weft_dom) (the DOM renderer) behind one module, `Weft`.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/weft rescript @rescript/runtime
```

Add `@e-cline/weft`, `@e-cline/weft_core` and `@e-cline/weft_dom` to the `dependencies` in your
`rescript.json`. (ReScript only sees modules from packages it's told about, and `Weft` is made of
aliases of the other two.)

## Using it

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

[`examples/weft_app`](../../examples/weft_app) is a complete app.

## What's in `Weft`

| Module / type   | From                     | What it is                                                          |
| --------------- | ------------------------ | ------------------------------------------------------------------- |
| `element`       | `WeftCore.Element.t`     | What a component returns and `Client.render` takes.                 |
| `Hooks`         | `WeftCore.Hooks`         | `useState`, `useReducer`, `useEffect`, `useMemo`, `useContext`, ... |
| `Ref`           | `WeftCore.Ref`           | The mutable box `Hooks.useRef` returns.                             |
| `Context`       | `WeftCore.Context`       | `make` and `provider`.                                              |
| `Memo`          | `WeftCore.Memo`          | Skip re-rendering a component whose props are unchanged.            |
| `Transition`    | `WeftCore.Transition`    | `start`: mark updates as non-urgent.                                |
| `ErrorBoundary` | `WeftCore.ErrorBoundary` | Catch errors thrown while rendering below it.                       |
| `Suspense`      | `WeftCore.Suspense`      | A fallback while a child waits on a promise (`Hooks.use`).          |
| `Lazy`          | `WeftCore.Lazy`          | An element that isn't ready yet, rendered in its place once it is.  |
| `Jsx`           | `WeftDom.Jsx`            | The JSX module; host tags take DOM props.                           |
| `Portal`        | `WeftDom.Portal`         | Render children into another DOM element.                           |
| `Client`        | `WeftDom.Client`         | `createRoot`, `render`, `unmount`, `flushSync`, `act`.              |
| `Dom`           | `WeftDom.Dom`            | The small set of DOM bindings the renderer and components need.     |

Each is an alias, so the types are the same as the originals' and the docs in `weft_core` and
`weft_dom` apply.

## What's not

The machinery for writing or testing a renderer stays in `@e-cline/weft_core`: `Reconciler`,
`Scheduler`, `HostConfig`, `JsxCore`, `TestRenderer`, `TestScheduler` and `TestJsx`. So does
`WeftCore.Jsx`, the JSX module without host tags, for components that should work under any
renderer. `@e-cline/weft_signals` is separate too.

## Bundle size

Free. A module alias compiles away: `Weft.Hooks.useState` becomes an import of `useState` from
`weft_core`'s `Hooks.res.js`, the same as writing `WeftCore.Hooks.useState`, so an app imports
exactly what it uses and a bundler drops the rest. `Weft.res.js` itself is never imported.
[`weft_core`'s size benchmark](../weft_core/benchmarks/size) is written against `Weft`, and its
numbers are the same as before.
