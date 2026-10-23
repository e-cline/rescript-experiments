/***
An element that isn't ready yet: a promise of an element, standing in for it until it settles.

```rescript
let chart = Weft.Lazy.fromPromise(
  import(Chart.make)->Promise.thenResolve(make => Weft.Jsx.jsx(make, {data: data})),
)

<Weft.Suspense fallback={<Spinner />}> chart </Weft.Suspense>
```

Until the promise settles, rendering it suspends, as `Hooks.use` does: the nearest `Suspense`
boundary shows its fallback (or, in a transition, the screen keeps its previous state), and renders
again once it has. A rejected promise throws its error, for an `ErrorBoundary` to catch. A promise
that has already settled by the time the element is rendered is read straight away, without
suspending.

A lazy element has no fiber of its own: what it resolves to is rendered in its place, as if it had
been there all along. So replacing a lazy element with the element it resolved to, or the other way
round, keeps everything below it, state included. That's what lets streamed server output (where a
part of the page may arrive as a placeholder first, and complete the next time) update the screen in
place. A lazy element has no key: the element it resolves to supplies one.

Make the element once (outside the component, or kept in state), not on every render: a new lazy
element is a new promise, which suspends again.
*/

/** An element standing for the one `promise` resolves to. */
let fromPromise: promise<Element.t> => Element.t

/**
For renderers that walk elements themselves (a server renderer, say): the promise a `Lazy` node
(`Element.classify` gives `Node({kind: Lazy, ...})`) stands for.
*/
let promiseOf: Element.node => promise<Element.t>
