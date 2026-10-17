# Plan: `res_fiber` -- a React-like component library in ReScript

A ReScript-native UI library: components are written with `@jsx.component`, rendered through a
React-style fiber tree with hooks, and drawn by a pluggable host renderer (DOM, an in-memory test
renderer, and anything else that implements the host interface). It doesn't use React at all.

## Status

Phases 0 to 4 are done (`packages/res_fiber`, `packages/res_fiber_dom`, `examples/res_fiber_app`),
and so are phase 5's error boundaries and portals; the `res_signals` bridge and the benchmarks are
still to do. Where they differ from the plan below:

- Additions: `Ref.t` (the `{current}` box `useRef` returns), `Jsx.Fragment` (a keyed fragment, since
  `<>` can't take one), `TestJsx` (the test renderer's JSX module), `useReducerWithMapState`, and
  `TestRenderer.scheduleRender`/`flushSync` for tests about effect timing.
- Sync and default updates render in a microtask (React renders default updates in a scheduler
  task), start to finish. Only transitions and idle work go through `Scheduler.S` and yield. Passive
  effects run in a `setTimeout` (or before the next render).
- Lanes are simpler than React's: one transition lane (no per-transition lanes or entanglement), and
  a render handles exactly one lane.
- Updates made while a concurrent render is paused go straight into the hooks' queues, rather than
  being held until the render ends as React does. A component rendered after the update sees it a
  little early; nothing is lost or reordered, which the lane-ordering fuzz test checks.
- `TestScheduler` keeps its tasks in a sorted array; only `Scheduler.Default` uses
  `res_priority_queue`, now a dependency of `res_fiber`.
- `Reconciler.S.flushAllWork` renders every root's pending work, transitions included, without
  yielding: what the renderers' `act` uses.
- When an exception escapes a root's render or commit, the root drops its pending lanes and renders
  again on its next update, instead of retrying (React would unmount it).
- The `res_common` dependency (for `Debug.debugAssert`) isn't needed yet. Hook-order checks always
  run, since a mismatch would otherwise read one hook's state as another's.
- Context providers follow `@rescript/react`:
  `module Provider = { let make = Context.provider(context) }` needs no `props` type, so the plan's
  `MakeProvider` functor wasn't needed. Provider and memo components are plain functions marked with
  hidden properties, which `jsx` reads to pick the element's kind.
- `Memo.memoCustomComparison` can't wrap a `@jsx.component` definition directly (the JSX PPX accepts
  only one-argument wrappers), so it's applied by shadowing `make`, as with `@rescript/react`'s
  `memoCustomCompareProps`.
- A memoized component whose props compare equal also checks its context dependencies, so a context
  change reaches it even when propagation wouldn't be needed.
- The DOM renderer has no separate `Style` or `PropDiff` modules: `DomProps.style` is a
  `dict<string>`, and `DomHost` does the diffing. Updates in event handlers render synchronously
  (through `flushSync`) rather than on a separate sync lane, which phase 4's lanes can refine.
  `DomHost` also restores focus after a commit that moved the focused element. SVG isn't supported
  yet (elements are created without a namespace).
- The example app's tests run in jsdom with Vitest rather than as a separate end-to-end script; the
  app was also checked by hand in a real browser.
- `ErrorBoundary` takes `fallback: (~error: exn, ~reset: unit => unit) => element` (labelled, so a
  call site reads clearly). Its state survives renders that are thrown away: `reset` bumps a
  generation number on the boundary's instance rather than clearing a flag.
- Errors in `useEffect` cleanups of removed components aren't caught by boundaries (the components
  have left the tree when those run); React does catch them.
- Portals are `Portal.create(~container, children)` in the core, wrapped per renderer. DOM events in
  a portal bubble through the DOM, not the component tree.
- Effect errors don't stop other effects: the first is kept and rethrown once the phase has run (the
  original JS error, not ReScript's `JsExn` wrapper).

## What was verified before writing this

These were checked against ReScript 12.3.1 (the version this workspace pins) in a scratch project,
because they decide how the library plugs into the compiler:

1. **The generic JSX transform works per file.** `@@jsxConfig({version: 4, module_: "Some.Jsx"})` at
   the top of a `.res` file switches that file to a custom JSX module. This matters because
   RESCRIPT.md (gap 17) found `jsx` is root-only in this monorepo, and the root is configured for
   React (`res_react_ui` depends on that). So the library can't take over the root `jsx` setting;
   every file that uses it opens with the `@@jsxConfig` line.
2. **The root's `"preserve": true` doesn't apply to a generic JSX module.** The output is plain
   `Jsx.jsx(...)` calls, never `<div>`, so Vite's React JSX transform never sees it.
3. **`module_` takes a dotted path**, so a namespaced `"ResFiberDom.Jsx"` works.
4. **A JSX module with no `Elements` submodule works**, and a lowercase tag in such a file is a
   compile error (`Core.Elements can't be found`). That gives renderer-agnostic components for free:
   write them against `ResFiber.Jsx` (no `Elements`) and the compiler rejects host tags.
5. **What the transform emits** (what `Jsx` has to accept):
   - `<Child a=1 />` → `Jsx.jsx(Child.make, {a: 1})`; with several children →
     `Jsx.jsxs(..., {children: [a, b]})`, a raw JS array.
   - `key="k"` → `Jsx.jsxKeyed(make, props, "k", undefined)`, the key passed positionally, not in
     props.
   - `<> ... </>` → `Jsx.jsxs(Jsx.jsxFragment, {children: [...]})`.
   - `<div ...>` → `Jsx.Elements.jsx("div", props)`, with `props` typed as `Jsx.Elements.props`.
   - `<Ctx.Provider value>` needs `Ctx.Provider` to declare `type props<'value, 'children>` and a
     `make` taking it (the same shape `@rescript/react` uses).

The scratch project's `MyJsx.res` (the minimal surface that compiled) is the starting point for
`JsxCore` below.

## Packages and layout

Two published packages plus an example, following the existing `res_*` conventions (ReScript source
only, `makeRescriptLibConfig()` with no TypeScript surface, `rescript-vitest` tests named
`*_test.res`, `.resi` for every public module, namespace per package).

```
packages/res_fiber/                 namespace ResFiber -- renderer-independent core
  src/
    Element.res(i)                  element representation + classification
    JsxCore.res(i)                  everything the JSX transform needs except `Elements`
    Jsx.res(i)                      = JsxCore (no Elements: renderer-agnostic components)
    Hooks.res(i)                    useState, useReducer, useEffect*, useLayoutEffect*, useMemo*,
                                    useCallback*, useRef, useContext, useSyncExternalStore
    Context.res(i)                  Context.make, MakeProvider
    Memo.res(i)                     memo, memoCustomComparison
    ErrorBoundary.res(i)            built-in error boundary component (phase 5)
    HostConfig.res                  `module type S` -- the pluggable rendering interface
    Scheduler.res(i)                `module type S` + default (MessageChannel) implementation
    TestScheduler.res(i)            deterministic scheduler with a manual clock, for tests
    Reconciler.res(i)               `Make(Host: HostConfig.S)` -- root API for a renderer
    TestRenderer.res(i)             in-memory host + `act`, published for consumers' tests
    internal/
      Fiber.res                     the fiber record, flags, tags
      Lanes.res                     priority bitmasks
      FiberRoot.res                 root record (current tree, pending lanes, scheduled callback)
      ChildReconciler.res           keyed child diffing
      RenderState.res               "currently rendering" globals the hooks read
      HookImpl.res                  hook storage, update queues, effect lists
      BeginWork.res                 per-tag render step (host-independent)
      ContextStack.res              provider value stack + change propagation
      WorkLoop.res                  scheduling, render loop, bailouts (host-independent parts)
  tests/                            TestRenderer-driven: reconciler, hooks, effects, context, fuzz

packages/res_fiber_dom/             namespace ResFiberDom -- DOM host renderer
  src/
    Dom.res                         minimal hand-written DOM bindings (no webapi dependency)
    DomProps.res                    the `Elements.props` record: attributes, style, events, ref
    Style.res(i)                    typed-ish style dict
    Jsx.res(i)                      include ResFiber.JsxCore + module Elements = DomElements
    DomHost.res                     HostConfig.S for the DOM
    PropDiff.res                    attribute / property / style / listener diffing
    Client.res(i)                   createRoot, render, unmount, flushSync
  tests/                            jsdom environment

examples/res_fiber_app/             Vite app (like res_tree_shaking): a todo list using every feature
```

Wiring for each new package, as for the existing ones: root `rescript.json` `dependencies`, a
`workspace:*` root `devDependency` (so the root `rescript build` resolves it), README table row, and
a changeset.

### Using it

```rescript
@@jsxConfig({version: 4, module_: "ResFiberDom.Jsx"})

module Counter = {
  @jsx.component
  let make = (~label: string) => {
    let (count, setCount) = ResFiber.Hooks.useState(() => 0)
    <button onClick={_ => setCount(c => c + 1)}>
      {ResFiberDom.Jsx.string(`${label}: ${Int.toString(count)}`)}
    </button>
  }
}

let root = ResFiberDom.Client.createRoot(container)
root->ResFiberDom.Client.render(<Counter label="Clicks" />)
```

## Design

### 1. Elements

`Element.t` is abstract. At runtime it is one of:

| Runtime value                       | Meaning                                                     |
| ----------------------------------- | ----------------------------------------------------------- |
| `null` / `undefined`                | renders nothing (`Jsx.null`, `None` children)               |
| JS string / number                  | text (`Jsx.string`, `Jsx.int`, `Jsx.float` are `%identity`) |
| JS array                            | a list of children (from `jsxs` or `Jsx.array`)             |
| `{$$fiber, tag, type_, props, key}` | a node: host, component, fragment, provider or memo         |

`Element.classify: t => view` (`Empty | Text(string) | List(array<t>) | Node(node)`) is the single
place that inspects the runtime shape, using `typeof`/`Array.isArray` and a `$$fiber` brand on node
objects. Everything else matches on `view`.

Component identity is the `make` function (physical equality), as in React: the same `make` in the
same position with the same key reuses the fiber.

### 2. The JSX module

`JsxCore` provides `element`, `component<'props>`, `componentLike`, `component` (`%identity`),
`jsx`, `jsxs`, `jsxKeyed`, `jsxsKeyed`, `array`, `null`, `string`, `int`, `float`, `jsxFragment`,
`fragmentProps`, `someElement`. `jsx` checks `type_ === jsxFragment` to tag fragments; memo and
provider `make` functions are tagged with a hidden property so `jsx` can recognize them without a
lookup table.

A renderer's `Jsx` is `include ResFiber.JsxCore` plus its own `Elements` submodule, so the element
type is shared: a component written against `ResFiber.Jsx` (no host tags) can be used from any
renderer, and a renderer's components return the same `element` type.

**Known soundness gap:** host props are erased in the element, so a `<div>` created through
`ResFiberDom.Jsx` could in principle be handed to a different renderer whose `props` record differs.
Parameterising `element` by renderer isn't possible, because the transform needs one concrete
`Jsx.element` type. Mitigation: document "one renderer per tree", and have host configs ignore
unknown props rather than crash.

### 3. The fiber tree

One mutable record type, host-independent (so hooks don't need to know the renderer):

```rescript
type rec t = {
  mutable tag: tag,                 // HostRoot | HostComponent | HostText | FunctionComponent
                                    // | Fragment | ContextProvider | Memo | ErrorBoundary
  key: Nullable.t<string>,
  mutable type_: unknown,           // `make` function or host tag string
  mutable pendingProps: unknown,
  mutable memoizedProps: unknown,
  mutable stateNode: unknown,       // host instance / text instance / FiberRoot; cast only inside Reconciler.Make
  mutable return: option<t>,
  mutable child: option<t>,
  mutable sibling: option<t>,
  mutable index: int,
  mutable alternate: option<t>,     // double buffering: current <-> work-in-progress
  mutable flags: int,               // Placement | Update | ChildDeletion | Ref | Passive | LayoutEffect
  mutable subtreeFlags: int,        // lets the commit phase skip clean subtrees
  mutable deletions: option<array<t>>,
  mutable memoizedState: unknown,   // function components: first hook; host root: element
  mutable updateQueue: unknown,     // function components: effect list; host: update payload
  mutable dependencies: option<array<contextDependency>>,
  mutable lanes: Lanes.t,
  mutable childLanes: Lanes.t,
}
```

All `unknown`/`Obj.magic` use stays in `internal/` behind typed accessors; public modules are fully
typed. `Debug.debugAssert` (from `res_common`) checks invariants in dev builds only.

**Double buffering:** `createWorkInProgress(current, pendingProps)` reuses `current.alternate` when
it exists, resetting flags, so steady-state updates allocate no new fibers. The root swaps `current`
at the end of commit.

### 4. Render phase

A loop over `workInProgress`, the same structure as React:

- `performUnitOfWork(fiber)` calls `beginWork`, then descends to `child`; with no child it calls
  `completeUnitOfWork`, which walks `sibling`/`return`, calling `completeWork` and bubbling
  `subtreeFlags` and `childLanes`.
- `beginWork` (host-independent, `BeginWork.res`), by tag:
  - **FunctionComponent:** set up `RenderState`, call `type_(props)`, then reconcile its children. A
    rerender requested during render (setState in render) loops, capped at 25 passes.
  - **HostComponent:** reconcile `props.children`.
  - **Fragment:** reconcile `props.children`.
  - **ContextProvider:** push the value; if it changed (`Object.is`), propagate (§7).
  - **Memo:** shallow-compare props; on equality with no pending lanes, bail out.
- **Bailout:** if `oldProps === newProps`, the fiber has no lanes in `renderLanes` and no context
  change, clone the children (`cloneChildFibers`) or, when `childLanes` is also clear, skip the
  whole subtree.
- `completeWork` (inside `Reconciler.Make`, since it calls the host):
  - **HostComponent on mount:** `Host.createInstance`, append all already-created host children,
    then `Host.finalizeInitialChildren`. The whole new subtree is built off-screen and attached with
    a single Placement at commit.
  - **HostComponent on update:** `Host.prepareUpdate(old, new)`; a `Some(payload)` is stored in
    `updateQueue` and flags `Update`.
  - **HostText:** create the text instance, or flag `Update` when the text changed.
  - **ContextProvider:** pop the value.

### 5. Child reconciliation (`ChildReconciler.res`)

React's algorithm, with two variants (`mountChildFibers` doesn't track side effects;
`reconcileChildFibers` does):

- Single element: scan old children for the same key, reuse it if the type matches, and delete the
  rest.
- Text: reuse a `HostText` sibling or replace it.
- Array: a first pass walks old and new in step while keys match. Then either delete the remainder
  or append the rest. Otherwise build a `Map` of remaining old fibers by key (or index), place each
  new child from it, and use `lastPlacedIndex` to decide which reused fibers need a `Placement`
  (move). Leftovers are deleted.
- Nested arrays become `Fragment` fibers, keyed by position.
- Dev-mode warning for duplicate keys, and for missing keys in arrays from `Jsx.array`.

### 6. Hooks

`RenderState` holds the fiber being rendered, the current and work-in-progress hook cursors, and
`renderLanes`. Calling a hook outside a render throws a clear error.

Each hook is a node in a linked list on `fiber.memoizedState`:
`{mutable memoizedState: unknown, mutable baseState, mutable baseQueue, mutable queue, mutable next}`.
In dev builds each node also records its hook kind, and a mismatch on rerender ("hook order
changed") fails loudly.

The API follows `@rescript/react` naming so it feels familiar:

| Hook                                                      | Notes                                                          |
| --------------------------------------------------------- | -------------------------------------------------------------- |
| `useState(init: unit => 's)` → `('s, ('s => 's) => unit)` | updater-only setter, like `@rescript/react`                    |
| `useReducer(reducer, init)`                               | shared implementation with `useState`                          |
| `useEffect`, `useEffect0` … `useEffect5`                  | `unit => option<unit => unit>`; deps compared with `Object.is` |
| `useLayoutEffect`, `useLayoutEffect0` … `5`               | runs synchronously after mutation                              |
| `useMemo0…5`, `useCallback0…5`, `useRef`                  |                                                                |
| `useContext(ctx)`                                         | records a dependency on the fiber                              |
| `useSyncExternalStore(~subscribe, ~getSnapshot)`          | always-sync lane; checks for tearing after render              |

**Updates:** each `useState`/`useReducer` queue is a circular list of `{lane, action, next}`.
`dispatch` (stable identity, bound once to the fiber and queue):

1. Picks a lane (`RenderState.requestUpdateLane`: Sync inside `flushSync` or a discrete event,
   Transition inside `startTransition`, Default otherwise).
2. Eager bailout: when neither alternate of the fiber has pending work, compute the new state now
   and return early if it is `Object.is`-equal.
3. Appends the update and marks `lanes` on the fiber and `childLanes` up to the root.
4. Calls `root.ensureScheduled()`.

On render, updates whose lane is in `renderLanes` are applied. Skipped (lower-priority) updates stay
in the `baseQueue` with the `baseState` from before the first skipped one, so they are re-applied in
order later. This is React's rebasing, and needed only once concurrent lanes land (phase 4).

**Effects:** each effect hook pushes `{tag: Layout | Passive, create, destroy, deps}` to the fiber's
effect list and flags the fiber when its deps changed.

### 7. Context

`Context.make(default)` returns `t<'v>` (`{id, default}`). Providers use a functor so the props type
the JSX transform requires comes out right:

```rescript
module Theme = {
  let context = ResFiber.Context.make(Light)
  module Provider = ResFiber.Context.MakeProvider({type t = theme; let context = context})
}
<Theme.Provider value=Dark> ... </Theme.Provider>
```

During render, `ContextStack` pushes each provider's value on begin and pops it on complete;
`useContext` reads the current value and appends `{context, memoizedValue}` to `fiber.dependencies`.
When a provider's value changes, `propagateContextChange` walks its subtree and, for each fiber
depending on that context, schedules the render lanes on it and its ancestors. This makes `memo`
bailouts safe.

### 8. Commit phase (always synchronous)

Inside `Reconciler.Make`, in three passes that use `subtreeFlags` to skip clean subtrees:

1. **Before mutation:** `Host.prepareForCommit(container)`.
2. **Mutation:**
   - Deletions: recursively unmount, which runs layout-effect destroys, detaches refs and runs
     `Host.removeChild` on the nearest host nodes only.
   - Placements: find the host parent and the next stable host sibling, then `insertBefore` or
     `appendChild`.
   - `commitUpdate` and `commitTextUpdate`.
   - Layout-effect destroys for updated fibers.
3. **Layout:** layout-effect creates (children before parents), attach refs, then
   `Host.resetAfterCommit`.

Then swap `root.current`. Passive effects (`useEffect`) are scheduled as a separate task: first
every destroy across the tree, then every create, matching React's ordering guarantee. Any pending
passive effects are flushed synchronously before the next render starts.

### 9. The pluggable host interface (`HostConfig.S`)

```rescript
module type S = {
  type container
  type instance
  type textInstance
  type node                                    // common supertype of instance and textInstance
  type props                                   // = the renderer's Jsx.Elements.props
  type updatePayload

  let instanceToNode: instance => node         // %identity in the DOM
  let textToNode: textInstance => node

  let createInstance: (~tag: string, ~props: props, ~container: container) => instance
  let createTextInstance: (string, ~container: container) => textInstance
  let appendInitialChild: (instance, node) => unit
  let finalizeInitialChildren: (instance, ~tag: string, ~props: props) => unit

  let prepareUpdate: (instance, ~tag: string, ~oldProps: props, ~newProps: props) => option<updatePayload>
  let commitUpdate: (instance, updatePayload, ~tag: string, ~oldProps: props, ~newProps: props) => unit
  let commitTextUpdate: (textInstance, ~oldText: string, ~newText: string) => unit

  let appendChild: (instance, node) => unit
  let insertBefore: (instance, node, ~before: node) => unit
  let removeChild: (instance, node) => unit
  let appendChildToContainer: (container, node) => unit
  let insertInContainerBefore: (container, node, ~before: node) => unit
  let removeChildFromContainer: (container, node) => unit
  let clearContainer: container => unit

  let prepareForCommit: container => unit
  let resetAfterCommit: container => unit

  // Ref values: what a `ref` on a host element receives
  type publicInstance
  let getPublicInstance: instance => publicInstance
}
```

`Reconciler.Make(Host)` returns:

```rescript
type root
let createRoot: Host.container => root
let render: (root, Element.t) => unit
let unmount: root => unit
let flushSync: (unit => 'a) => 'a
let batchedUpdates: (unit => 'a) => 'a      // what renderers wrap event handlers in
```

The scheduler is a second pluggable seam: `Scheduler.S` (`now`, `scheduleCallback(priority, cb)`,
`cancelCallback`, `shouldYield`, `requestPaint`). The default implementation keeps its task queue in
`res_priority_queue`'s `MutablePriorityQueue`, ordered by expiration time then insertion id, and
drives it with a `MessageChannel` and a 5 ms slice. `TestScheduler` has a manual clock and
`flushAll`/`advanceTime` for deterministic tests. A renderer picks its scheduler:
`Reconciler.MakeWithScheduler(Host, Sched)`, with `Make(Host)` using the default.

Hooks find their root's scheduler through `FiberRoot` (a closure the functor stores in the
`HostRoot` fiber's `stateNode`), which keeps hooks host- and scheduler-independent.

### 10. Renderers

**TestRenderer (in `res_fiber`):** nodes are plain records
`{tag, mutable props, mutable children: array<node>, mutable text}`. It provides `toTree` and
`toString` snapshots, `findByTestId`, and an **operation log** (`"create li#a"`,
`"insertBefore li#c li#a"`, `"update div {class}"`, `"remove li#b"`) so tests can assert both the
result and that the reconciler did the minimum work. `act(fn)` runs `fn` in a batch, then drains the
`TestScheduler`, including passive effects.

**DOM (`res_fiber_dom`):**

- `DomProps.props` record: `id`, `className`, `style`, `href`, `src`, `value`, `checked`,
  `disabled`, `placeholder`, `type_`, `htmlFor`, `role`, `tabIndex`, `ariaLabel`, `dataTestId`,
  `ref`, `children`, and handlers (`onClick`, `onInput`, `onChange`, `onKeyDown`, `onSubmit`,
  `onFocus`, `onBlur`, …) typed `Dom.event => unit`. This starts as a deliberate subset and grows on
  demand.
- `PropDiff` produces an update payload as an array of `(name, oldValue, newValue)` changes. Each
  prop maps to an attribute, a property (`value`, `checked`) or a style key, and `style` objects are
  diffed key by key.
- Events: the first cut attaches listeners directly to elements, stored in a per-instance table so
  that swapping a handler is one table write, not a remove/add. Every handler runs inside
  `batchedUpdates`, and discrete events (click, keydown, input) use the Sync lane. Delegating to a
  root listener is a later optimisation, not a requirement.
- `Client.createRoot(element)` returns `{render, unmount}`.

## Phases

Each phase ends green (`pnpm run build`, `pnpm run test`, `pnpm run check`) and is a reviewable
commit or PR on its own.

**Phase 0 -- Scaffold and pin the JSX contract**

- Create both packages with configs, wiring, empty `.resi` files, and a changeset.
- Move the scratch `MyJsx.res` probe into a test, `Jsx_test.res`, so the transform's output shape is
  locked in by CI: it compiles a component, keyed children, a fragment and a provider through
  `ResFiber.Jsx`, then checks the elements produced.
- Confirm `@@jsxConfig` behaves the same inside the real monorepo build as in the scratch project.

**Phase 1 -- Synchronous core (TestRenderer only)**

- `Element`, `JsxCore`, `Fiber`, `FiberRoot`, `ChildReconciler`, `BeginWork`, `WorkLoop` (sync lane
  only, rendering to completion), commit with mutation only, `Reconciler.Make`, `TestRenderer`.
- Hooks: `useState`, `useReducer`, `useRef`, `useMemo*`, `useCallback*`, plus automatic batching of
  updates in one task via a microtask.
- Tests:
  - mount, update and unmount of nested trees;
  - text updates;
  - keyed reorder and insert/delete in the middle, asserting the operation log is minimal;
  - type change remounts;
  - state is preserved when position and type are unchanged, and reset when the key changes;
  - setState during render;
  - eager bailout;
  - hook-order violation fails in dev.

**Phase 2 -- Effects, refs, context, memo**

- `useEffect*`, `useLayoutEffect*` with cleanup, host `ref`, `Context`, `Memo`, bailout via
  `childLanes`, `useSyncExternalStore`.
- Tests:
  - effect ordering: child before parent; all destroys before any creates; unmount runs destroys;
  - deps semantics for `0`/`N`/none;
  - a context change reaches consumers below a `memo` bailout;
  - refs are set before layout effects and cleared on unmount.
- **Fuzz test**, in the style of `res_signals/tests/Fuzz_test.res`: a seeded PRNG generates random
  keyed trees and random update sequences. After each step, assert that the TestRenderer tree equals
  a direct rendering of the expected element tree, and that host-node identity is kept for every key
  that survived.

**Phase 3 -- DOM renderer and example**

- `res_fiber_dom` in full, plus jsdom tests: attributes vs properties, style diffing, event handler
  swaps, controlled `<input value>`, and `ref`.
- `examples/res_fiber_app`: a todo app (list with keys, input, filter context, `useEffect` for
  persisting to `localStorage`) under Vite, with an end-to-end test like `res_tree_shaking`'s.

**Phase 4 -- Concurrent rendering**

- Lanes beyond Sync (Default, Transition, Idle); the scheduler with time slicing via `shouldYield`;
  interruptible render loop; `prepareFreshStack` when higher-priority work arrives.
- Hook `baseQueue` rebasing; `startTransition`, `useTransition`, `useDeferredValue`.
- Tests on `TestScheduler`:
  - a long render yields;
  - a sync update interrupts a transition and the transition restarts;
  - skipped updates are re-applied in order (the classic React rebasing example);
  - no tearing with `useSyncExternalStore`.

**Phase 5 -- Errors and extras (each optional)**

- `ErrorBoundary` (`~fallback: (exn, ~reset: unit => unit) => element`), a special fiber tag that
  catches during render (unwind to the nearest boundary and re-render it with the error) and during
  commit.
- Portals: `Portal.make(~container)`, a fiber whose host parent is a different container.
- A `res_signals` bridge (`ResFiber`-side `useAtom`/`useComputed` on `useSyncExternalStore`), as a
  third package or in the example, to keep the core free of dependencies.
- A benchmark package (`res_fiber/benchmarks`, on `tools/benchmarking`) covering mounting, updating
  and reordering a list of 1k–10k rows on the TestRenderer.

Out of scope: class components, Suspense and `use`, server rendering and hydration, StrictMode
double-invoking, DevTools integration.

## Risks and open decisions

- **Concurrent rebasing is the hardest part** to get right (update queues shared between current and
  alternate, restarting renders). Phases 1–3 deliberately ship a fully working synchronous library
  first, so phase 4 can't block having a usable result.
- **Functor vs. runtime host-config record.** The plan uses a functor (`Reconciler.Make(Host)`):
  host types such as `instance` stay typed, and it matches the module-type style `res_trees` settled
  on. The cost is that functor bodies compile to a JS function returning a module object, which
  tree-shakes worse than top-level functions. `res_tree_shaking` can measure that once phase 3
  lands.
- **Host props typing is per renderer, not per tag.** One `Elements.props` record covers every DOM
  tag, as `@rescript/react`'s `JsxDOM.domProps` does. Per-tag typing isn't something the generic
  transform supports.
- **Naming:** `res_fiber` / `res_fiber_dom` / namespaces `ResFiber`, `ResFiberDom` are proposals;
  renaming is cheap before phase 0 lands.
