/***
Catches exceptions from the components below it and renders a fallback instead of them.

```rescript
<WeftCore.ErrorBoundary
  fallback={(~error, ~reset) =>
    <ErrorPanel message={WeftCore.ErrorBoundary.message(error)} onRetry=reset />}>
  <Dashboard />
</WeftCore.ErrorBoundary>
```

It catches what a component below it throws while rendering, and what their effects
(`useLayoutEffect`, `useEffect`) throw. Rendering stops at the boundary and continues with its
fallback, so nothing from the failed subtree is committed; an error from an effect shows the fallback
in a render straight after. The boundary keeps showing the fallback until `reset` is called (or it's
removed): `reset` renders the children again.

It doesn't catch errors in its own `fallback` (they go to the next boundary up), in event handlers,
or in the `useEffect` cleanups of components being removed (which run after they've left the tree).
An error with no boundary above it propagates out of whatever started the render, as before.

`fallback` is called while the boundary renders, so it can't use hooks; return a component element if
the fallback needs state.
*/

type props = {
  fallback: (~error: exn, ~reset: unit => unit) => Element.t,
  children: Element.t,
}

let make: JsxCore.component<props>

/**
A message for `error`: a JS error's `message`, or a ReScript exception's name (its `RE_EXN_ID`).
*/
let message: exn => string
