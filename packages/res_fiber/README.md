# @e-cline/res_fiber

A React-like component library written in ReScript, with no React underneath: components are
ordinary `@jsx.component` functions, state lives in hooks, and a fiber reconciler (the same design
as React's) works out what changed and hands the changes to a pluggable host renderer.

This is an early stage of the [plan](../../docs/res_fiber_plan.md). What works:

- `@jsx.component` components, host elements, text, fragments (`<>`, and `<Jsx.Fragment key>`),
  keyed and unkeyed lists.
- React's child reconciliation: nodes are reused by key and type, and moves, insertions and removals
  touch only what changed.
- `useState`, `useReducer`, `useReducerWithMapState`, `useRef`, `useMemo0`–`5`, `useCallback0`–`5`.
- `useEffect` and `useLayoutEffect` (each with `0`–`5` dependency variants), with React's ordering:
  layout effects in the commit, passive effects after it, every cleanup before any effect.
- `ref` props on host elements, `Context` with `useContext`, `Memo.memo`, and
  `useSyncExternalStore`.
- Automatic batching (updates in one task render once, in a microtask), `flushSync`, setting state
  while rendering, skipping components whose props and state didn't change.
- `TestRenderer`: an in-memory renderer that logs every host operation.

Not yet: a DOM renderer, concurrent rendering, error boundaries.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/res_fiber rescript @rescript/runtime
```

Add `"@e-cline/res_fiber"` to the `dependencies` in your `rescript.json`. The modules are under the
`ResFiber` namespace.

## Writing components

A file opts in to this library's JSX with a `@@jsxConfig` line naming a JSX module:

```rescript
@@jsxConfig({version: 4, module_: "ResFiber.TestJsx"})

module Counter = {
  @jsx.component
  let make = (~label: string) => {
    let (count, setCount) = ResFiber.Hooks.useState(() => 0)
    <button id="counter" onClick={() => setCount(c => c + 1)}>
      {ResFiber.TestJsx.string(`${label}: ${Int.toString(count)}`)}
    </button>
  }
}
```

The JSX module decides which host tags exist and what props they take, so each renderer has its own.
`ResFiber.Jsx` has no host tags at all: a component written against it can only compose other
components, and works under any renderer. A `<div>` in such a file is a compile error.

`@@jsxConfig` works per file, so it doesn't need the project's `jsx` setting (which, in this
repository, belongs to React). ReScript lowers the JSX to function calls either way, even when the
project sets `"preserve": true`.

Hooks follow `@rescript/react`'s names and the usual rules: call them unconditionally, in the same
order on every render. Breaking the order throws.

### Effects

`useLayoutEffect` runs synchronously once the host is updated, before the commit returns (an update
it makes renders straight away). `useEffect` runs afterwards: in a `setTimeout`, or before the next
render, whichever comes first. Within each kind, children run before parents, and every cleanup due
in a commit runs before any effect. An exception from an effect doesn't stop the others; the first
one is rethrown once they've all run.

### Context

```rescript
module Theme = {
  let context = ResFiber.Context.make("light")
  module Provider = {
    let make = ResFiber.Context.provider(context)
  }
}

<Theme.Provider value="dark"> <Toolbar /> </Theme.Provider>
// inside Toolbar, or anything below it:
let theme = ResFiber.Hooks.useContext(Theme.context)
```

A consumer renders again when its provider's value changes, even past components that skipped
rendering.

### Memo

```rescript
module Row = {
  @jsx.component
  let make = ResFiber.Memo.memo((~label: string) => ...)
}
```

`Memo.memo` compares props field by field with `Object.is`. For a custom comparison, shadow `make`
with `Memo.memoCustomComparison(make, (a, b) => ...)`, since `@jsx.component` only accepts a
one-argument wrapper.

## Testing with `TestRenderer`

```rescript
let renderer = ResFiber.TestRenderer.create()
renderer->ResFiber.TestRenderer.render(<Counter label="Clicks" />)
renderer->ResFiber.TestRenderer.click("counter")
renderer->ResFiber.TestRenderer.toString // `<button id="counter">Clicks: 1</button>`
renderer->ResFiber.TestRenderer.ops // ["create \"Clicks: 0\"", ..., "text \"Clicks: 0\" -> \"Clicks: 1\""]
```

`ops` lists the host operations performed (`create`, `append`, `insert ... before`, `remove`,
`update`, `text`), so a test can check that an update did no more than it had to. `render`, `click`,
`input` and `unmount` run inside `act`, which also runs effects (and renders any updates they make)
before returning. To observe timing, `scheduleRender` and `flushSync` render without running
`useEffect`s.

## Writing a renderer

A renderer implements `HostConfig.S` (create instances and text, append, insert and remove children,
compute and apply prop updates) and gets its API from `Reconciler.Make`:

```rescript
module Renderer = ResFiber.Reconciler.Make(MyHost)
let root = Renderer.createRoot(container)
Renderer.flushSync(() => Renderer.render(root, element))
```

It also provides a JSX module: `include ResFiber.JsxCore` plus an `Elements` submodule whose `props`
record is the renderer's host props, built on `JsxCore.hostJsx`. `TestJsx` and `TestRenderer` are a
complete example.

## How it works

- **Elements** are plain values: `null`, a string or number, an array, or a node record
  (`Element.classify` tells them apart).
- **Fibers** form two trees: `current` (on screen) and the work-in-progress tree a render builds
  from it, reusing each fiber's `alternate`.
- **Rendering** walks the tree from the root, skipping subtrees with no pending updates, renders
  components, and diffs their output against the current children. New host nodes are built
  off-screen, bottom up.
- **Committing** applies the recorded insertions, moves, updates and removals to the host in one go,
  then attaches refs and runs layout effects; passive effects follow later.

An exception thrown while rendering leaves the screen as it was and propagates to whatever started
the render. The updates that render was processing are lost.
