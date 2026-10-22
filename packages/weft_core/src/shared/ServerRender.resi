/***
For server renderers: calling components outside the reconciler. Two kinds, two calls:

- `run`, for server components, which have no state: hooks that keep state or run effects fail.
- `renderComponent`, for client components (entrypoints, and what they render) rendered to HTML on
  the server: hooks work, as on a first render that never commits.

A server renderer calls component functions itself, with no fibers, so the hooks that keep state or
run effects have nowhere to keep it. `run` marks the call as a server render, so those hooks fail
with an error saying so (rather than "called outside a component"), while `Hooks.use` still works:
a promise that hasn't settled throws its `Suspended` exception, for the renderer to wait on and call
the component again.
*/

/**
Calls `f` as a server render. Only the synchronous part of `f` counts: the mark is removed when it
returns or throws, so a client render that runs afterwards (in the same process, as in a test) isn't
affected. A render that `run` is called from the middle of is set aside for the duration and
restored afterwards.
*/
let run: (unit => 'a) => 'a

/** Whether a server render (`run`) is in progress. */
let isRunning: unit => bool

/**
The promise a server render suspended on, if `error` (what `run` threw) is a suspension: `Hooks.use`
on a promise that hasn't settled. The renderer waits for it, and calls the component again.
*/
let suspendedOn: exn => option<promise<unknown>>

/** A context, and the value a provider above the component gave it. */
type contextValue

let contextValue: (Context.t<'value>, 'value) => contextValue

type options = {
  /** The providers above the component, outermost first: what its `useContext` reads. */
  contexts: array<contextValue>,
}

/**
Calls a client component (an entrypoint, or a component it renders) on the server, for an HTML
renderer, returning what it rendered: as the mount of a component that's in no tree, so its hooks
work as on a first render that never commits.

- `useState`, `useReducer`, `useRef`, `useMemo` and `useCallback` give their initial values; a
  component that sets its own state while rendering renders again, as on the client.
- `useContext` reads `options.contexts` (or the context's default).
- `useEffect` and `useLayoutEffect` never run, and an update made later (from a handler kept
  somewhere) is dropped.
- `useSyncExternalStore` reads its `getServerSnapshot`, and fails without one.
- `useTransition` is never pending; `useDeferredValue` gives its value.
- `Hooks.use` on a pending promise throws its `Suspended` (see `suspendedOn`), for the renderer to
  wait on and call the component again.

Anything in progress (a client render, a server component's `run`) is set aside for the call and
restored after, however it ends.
*/
let renderComponent: ('props => Element.t, 'props, options) => Element.t

/** Whether `renderComponent` is calling a component. */
let isRenderingComponent: unit => bool
