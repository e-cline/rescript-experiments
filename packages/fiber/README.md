# @e-cline/fiber

A React-like component library written in ReScript, with no React underneath: components are
ordinary `@jsx.component` functions, state lives in hooks, and a fiber reconciler (the same design
as React's) works out what changed and hands the changes to a pluggable host renderer.

This is an early stage of the [plan](../../docs/fiber_plan.md). What works:

- `@jsx.component` components, host elements, text, fragments (`<>`, and `<Jsx.Fragment key>`),
  keyed and unkeyed lists.
- React's child reconciliation: nodes are reused by key and type, and moves, insertions and removals
  touch only what changed.
- React's key warnings in development builds: two children with the same key, and children without a
  key in a `Jsx.array` list.
- `useState`, `useReducer`, `useReducerWithMapState`, `useRef`, `useMemo0`–`5`, `useCallback0`–`5`.
- `useEffect` and `useLayoutEffect` (each with `0`–`5` dependency variants), with React's ordering:
  layout effects in the commit, passive effects after it, every cleanup before any effect.
- `ref` props on host elements, `Context` with `useContext`, `Memo.memo`, and
  `useSyncExternalStore`.
- Automatic batching (updates in one task render once, in a microtask), `flushSync`, setting state
  while rendering, skipping components whose props and state didn't change.
- Concurrent rendering: `Transition.start`, `useTransition` and `useDeferredValue`. Transitions
  render in time slices, more urgent updates interrupt them, and skipped updates are applied later
  in their original order.
- `ErrorBoundary`, catching errors from rendering and effects below it, and `Portal`, rendering
  children into another container.
- `Suspense` and `Hooks.use(promise)`: a fallback while components below wait for a promise.
- `TestRenderer`: an in-memory renderer that logs every host operation, with `TestScheduler` to step
  through concurrent renders.

To render into a browser page, use [`@e-cline/fiber_dom`](../fiber_dom); to read `signals` atoms and
computeds from components, [`@e-cline/fiber_signals`](../fiber_signals). [`benchmarks/`](benchmarks)
measures the reconciler on lists of up to 10,000 rows, and the size of a production bundle:
`vp run size`, from the repository root, prints it for a counter, an app using the whole API, and
[the todo app](../../examples/fiber_app), minified and compressed (see
[Bundle size](benchmarks/README.md#bundle-size)).

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/fiber rescript @rescript/runtime
```

Add `"@e-cline/fiber"` to the `dependencies` in your `rescript.json`. The modules are under the
`Fiber` namespace.

## Writing components

A file opts in to this library's JSX with a `@@jsxConfig` line naming a JSX module:

```rescript
@@jsxConfig({version: 4, module_: "Fiber.TestJsx"})

module Counter = {
  @jsx.component
  let make = (~label: string) => {
    let (count, setCount) = Fiber.Hooks.useState(() => 0)
    <button id="counter" onClick={() => setCount(c => c + 1)}>
      {Fiber.TestJsx.string(`${label}: ${Int.toString(count)}`)}
    </button>
  }
}
```

The JSX module decides which host tags exist and what props they take, so each renderer has its own.
`Fiber.Jsx` has no host tags at all: a component written against it can only compose other
components, and works under any renderer. A `<div>` in such a file is a compile error.

`@@jsxConfig` works per file, so it doesn't need to take over the project's `jsx` setting, though
the project must turn JSX on (here, the root `rescript.json`'s `"jsx": {"version": 4}`). ReScript
lowers the JSX to function calls either way, even when the project sets `"preserve": true`, so the
output is plain `.res.js`.

Hooks follow `@rescript/react`'s names and the usual rules: call them unconditionally, in the same
order on every render. Breaking the order throws in development (production builds skip the check,
as React's do).

### Effects

`useLayoutEffect` runs synchronously once the host is updated, before the commit returns (an update
it makes renders straight away). `useEffect` runs afterwards: in a `setTimeout`, or before the next
render, whichever comes first. Within each kind, children run before parents, and every cleanup due
in a commit runs before any effect. An exception from an effect doesn't stop the others; the first
one is rethrown once they've all run.

### Context

```rescript
module Theme = {
  let context = Fiber.Context.make("light")
  module Provider = {
    let make = Fiber.Context.provider(context)
  }
}

<Theme.Provider value="dark"> <Toolbar /> </Theme.Provider>
// inside Toolbar, or anything below it:
let theme = Fiber.Hooks.useContext(Theme.context)
```

A consumer renders again when its provider's value changes, even past components that skipped
rendering.

### Transitions

```rescript
let (isPending, startTransition) = Fiber.Hooks.useTransition()
// in a handler:
startTransition(() => setResults(_ => search(query)))
```

Each update has a lane: `flushSync` and event handlers (in `fiber_dom`) are sync, updates in
`Transition.start` are transitions, and everything else is default. Sync and default updates render
in a microtask, start to finish. A transition renders in scheduler tasks, stopping every 5 ms (by
default) to let the browser handle input; an urgent update arriving meanwhile throws the unfinished
render away, renders on its own (skipping the transition's updates), and the transition then starts
again. `useDeferredValue(value)` shows the previous value during urgent renders and catches up in a
transition. A store read with `useSyncExternalStore` that changed while a transition was paused
makes it render again, without stopping, so no commit mixes old and new values.

The scheduler is pluggable: `Reconciler.MakeWithScheduler(Host, Sched)` takes any `Scheduler.S`;
`Reconciler.Make(Host)` uses `Scheduler.Default`.

### Error boundaries

```rescript
<Fiber.ErrorBoundary
  fallback={(~error, ~reset) =>
    <ErrorPanel message={Fiber.ErrorBoundary.message(error)} onRetry=reset />}>
  <Dashboard />
</Fiber.ErrorBoundary>
```

An exception thrown while a component below renders stops rendering at the nearest boundary, which
renders its fallback instead (in the same render, so nothing from the failed subtree commits). An
exception from an effect below shows the fallback in a render straight after. `reset` renders the
children again. An error in a fallback goes to the next boundary up; with no boundary, it propagates
as before.

### Suspense

```rescript
let user = fetchUser(id) // made once, outside the component (or cached)

module Profile = {
  @jsx.component
  let make = () => <h1> {Jsx.string(Fiber.Hooks.use(user).name)} </h1>
}

<Fiber.Suspense fallback={<Spinner />}> <Profile /> </Fiber.Suspense>
```

`Hooks.use(promise)` returns what the promise resolved to. Until it settles, the nearest `Suspense`
boundary shows its fallback, and renders its children again once it has; a rejection goes to the
nearest `ErrorBoundary`. Pass the same promise every render, since a render that suspends is thrown
away. Children that suspend after being shown stay mounted behind the fallback, hidden, keeping
their state. In a transition, a boundary showing its children doesn't fall back at all: the screen
keeps its previous state (and `useTransition`'s `isPending` stays `true`) until the data arrives.

### Portals

`Portal.create(~container, children)` renders `children` into another container of the same renderer
while they stay in place in the tree: context, error boundaries and effects behave as if they were
where the portal is. Renderers wrap it with their container type: `TestRenderer.portal` (with
`TestRenderer.createTarget`) and `FiberDom.Portal`.

### Memo

```rescript
module Row = {
  @jsx.component
  let make = Fiber.Memo.memo((~label: string) => ...)
}
```

`Memo.memo` compares props field by field with `Object.is`. For a custom comparison, shadow `make`
with `Memo.memoCustomComparison(make, (a, b) => ...)`, since `@jsx.component` only accepts a
one-argument wrapper.

## Error codes

In development, misusing the library throws an error that says what went wrong. Production builds
leave the messages out, throwing `Fiber error <code>` instead:

| Code | Development message                                                                                          |
| ---: | ------------------------------------------------------------------------------------------------------------ |
|    1 | Hooks can only be called while a function component is rendering.                                            |
|    2 | Rendered more hooks than during the previous render.                                                         |
|    3 | Rendered fewer hooks than during the previous render.                                                        |
|    4 | Too many re-renders: a component is setting its own state on every render.                                   |
|    5 | Maximum update depth exceeded: a component keeps updating state while rendering or in a layout effect.       |
|    6 | Updates keep scheduling more updates (from `act`, or `TestRenderer`).                                        |
|    7 | Can't render into a root that was unmounted.                                                                 |
|    8 | A component suspended (`Hooks.use` on a promise that hasn't settled) with no `<Suspense>` boundary above it. |
|    9 | A host node has no host parent (a bug in Fiber or the renderer).                                             |
|   10 | Context stack underflow (a bug in Fiber).                                                                    |
|   11 | `jsxFragment` is a marker for `<>...</>`, not a component to call.                                           |
|   12 | A value that isn't an element was rendered.                                                                  |

Codes don't change once published: a new error gets the next number.

## Testing with `TestRenderer`

```rescript
let renderer = Fiber.TestRenderer.create()
renderer->Fiber.TestRenderer.render(<Counter label="Clicks" />)
renderer->Fiber.TestRenderer.click("counter")
renderer->Fiber.TestRenderer.toString // `<button id="counter">Clicks: 1</button>`
renderer->Fiber.TestRenderer.ops // ["create \"Clicks: 0\"", ..., "text \"Clicks: 0\" -> \"Clicks: 1\""]
```

`ops` lists the host operations performed (`create`, `append`, `insert ... before`, `remove`,
`update`, `text`), so a test can check that an update did no more than it had to. `render`, `click`,
`input` and `unmount` run inside `act`, which renders everything pending (transitions included) and
runs effects before returning. To observe timing, `scheduleRender` and `flushSync` render without
running `useEffect`s, and transitions wait on `TestScheduler`: `flushTask` runs one time slice,
`flushAll` the rest, and a component can call `TestScheduler.advanceTime` to take time to render.

## Writing a renderer

A renderer implements `HostConfig.S` (create instances and text, append, insert and remove children,
compute and apply prop updates) and gets its API from `Reconciler.Make`:

```rescript
module Renderer = Fiber.Reconciler.Make(MyHost)
let root = Renderer.createRoot(container)
Renderer.flushSync(() => Renderer.render(root, element))
```

It also provides a JSX module: `include Fiber.JsxCore` plus an `Elements` submodule whose `props`
record is the renderer's host props, built on `JsxCore.hostJsx` (and `JsxCore.hostJsxs` for
`Elements.jsxs`, which marks written-out children so they aren't warned about for having no keys).
`TestJsx` and `TestRenderer` are a complete example.

## How it works

- **Elements** are plain values: `null`, a string or number, an array, or a node record
  (`Element.classify` tells them apart).
- **Fibers** form two trees: `current` (on screen) and the work-in-progress tree a render builds
  from it, reusing each fiber's `alternate`.
- **Rendering** walks the tree from the root, skipping subtrees with no pending updates in the lane
  being rendered, renders components, and diffs their output against the current children. New host
  nodes are built off-screen, bottom up. A concurrent render can stop between fibers and pick up
  where it left off.
- **Committing** applies the recorded insertions, moves, updates and removals to the host in one go,
  then attaches refs and runs layout effects; passive effects follow later.

An exception thrown while rendering leaves the screen as it was and propagates to whatever started
the render. The updates that render was processing are lost.
