/***
The machinery behind `Hooks`: which fiber is rendering, its list of hooks, and state updates.

A function component's hooks are a linked list on its fiber's `memoizedState`, in call order. On
mount each hook call appends a node. On update each call clones the next node of the current fiber's
list (so the state on screen is never mutated by a render that might not commit). A component that
sets its own state while rendering is called again straight away (a "rerender"), reusing the nodes
the previous pass built.

Each node records which hook made it, so in development calling hooks in a different order from one
render to the next fails with a clear message instead of reading one hook's state as another's.
*/

type kind =
  | State
  | Reducer
  | Ref
  | Memo
  | Effect
  | LayoutEffect
  | Deferred
  | Id

type rec hook = {
  kind: kind,
  mutable memoizedState: unknown,
  /** State hooks: the state the `baseQueue` applies to. */
  mutable baseState: unknown,
  /** State hooks: updates a render skipped (lower priority), and every update after them. */
  mutable baseQueue: unknown,
  mutable queue: unknown,
  mutable next: option<hook>,
}

type mode =
  | Mount
  | Update
  | Rerender

type renderState = {
  mutable fiber: option<Fiber.t>,
  /** The node of the current (committed) fiber's list matching the last hook called. */
  mutable currentHook: option<hook>,
  /** The node of the work-in-progress list for the last hook called. */
  mutable workInProgressHook: option<hook>,
  mutable mode: mode,
  mutable didScheduleRenderPhaseUpdate: bool,
  /** Whether the fiber being rendered got new props or state: if not, its old output is reused. */
  mutable didReceiveUpdate: bool,
  mutable renderLanes: Lanes.t,
}

let state = {
  fiber: None,
  currentHook: None,
  workInProgressHook: None,
  mode: Mount,
  didScheduleRenderPhaseUpdate: false,
  didReceiveUpdate: false,
  renderLanes: Lanes.none,
}

/** The lane updates get when nothing more specific applies; `flushSync` switches it to `sync`. */
let updateLane = ref(Lanes.defaultLane)

let reset = () => {
  state.fiber = None
  state.currentHook = None
  state.workInProgressHook = None
  state.didScheduleRenderPhaseUpdate = false
}

external hookToUnknown: hook => unknown = "%identity"
external unknownToHook: unknown => Nullable.t<hook> = "%identity"

let firstHook = (fiber: Fiber.t): option<hook> =>
  unknownToHook(fiber.memoizedState)->Nullable.toOption

/** Whether a server renderer is calling a component (`ServerRender.run`). */
let onServer = ref(false)

/** Whether the reconciler is hydrating the component it's rendering (`useSyncExternalStore` reads its server snapshot then). */
let hydrating = ref(false)

let renderingFiber = (): Fiber.t =>
  switch state.fiber {
  | Some(fiber) => fiber
  | None if onServer.contents =>
    Errors.fail(
      14,
      Common.Env.isDev
        ? "WeftCore: this hook can't be used in a component rendered on the server. Only Hooks.use works there; a component with state or effects has to run in the browser (an entrypoint)."
        : "",
    )
  | None =>
    Errors.fail(
      1,
      Common.Env.isDev
        ? "WeftCore: hooks can only be called while a function component is rendering"
        : "",
    )
  }

/**
Fails as `renderingFiber` does, unless a component is rendering on either side: what `Hooks.use`
checks, since suspending is the one thing that works on the server too.
*/
let checkCanSuspend = () =>
  if !onServer.contents {
    renderingFiber()->ignore
  }

/**
Calls `f` as a server render (`ServerRender.run`), with any render in progress set aside, so a hook
called in `f` can't reach its fiber. Both are restored however `f` ends.
*/
let renderOnServer = (f: unit => 'a): 'a => {
  let fiber = state.fiber
  let wasOnServer = onServer.contents
  state.fiber = None
  onServer := true
  let restore = () => {
    state.fiber = fiber
    onServer := wasOnServer
  }
  switch f() {
  | result =>
    restore()
    result
  // A JS error is rethrown as itself, not wrapped in `JsExn`.
  | exception JsExn(thrown) =>
    restore()
    JsExn.throw(thrown)
  | exception error =>
    restore()
    throw(error)
  }
}

let kindName = (kind: kind) =>
  switch kind {
  | State => "useState"
  | Reducer => "useReducer"
  | Ref => "useRef"
  | Memo => "useMemo/useCallback"
  | Effect => "useEffect"
  | LayoutEffect => "useLayoutEffect"
  | Deferred => "useDeferredValue"
  | Id => "useId"
  }

/** Development only, as in React: production builds skip the check (and its messages). */
let checkKind = (hook: hook, kind: kind) =>
  if Common.Env.isDev && hook.kind != kind {
    JsError.throwWithMessage(
      `WeftCore: hooks were called in a different order from the previous render (expected ${kindName(
          hook.kind,
        )}, got ${kindName(
          kind,
        )}). Hooks must be called unconditionally, in the same order on every render.`,
    )
  }

let appendHook = (fiber: Fiber.t, hook: hook) => {
  switch state.workInProgressHook {
  | Some(previous) => previous.next = Some(hook)
  | None => fiber.memoizedState = hookToUnknown(hook)
  }
  state.workInProgressHook = Some(hook)
}

let mountHook = (fiber: Fiber.t, kind: kind): hook => {
  let hook = {
    kind,
    memoizedState: Unsafe.nothing,
    baseState: Unsafe.nothing,
    baseQueue: Unsafe.nothing,
    queue: Unsafe.nothing,
    next: None,
  }
  appendHook(fiber, hook)
  hook
}

let updateHook = (fiber: Fiber.t, kind: kind): hook => {
  let nextCurrentHook = switch state.currentHook {
  | Some(hook) => hook.next
  | None =>
    switch fiber.alternate {
    | Some(current) => firstHook(current)
    | None => None
    }
  }
  let nextWorkInProgressHook = switch state.workInProgressHook {
  | Some(hook) => hook.next
  | None => firstHook(fiber)
  }
  state.currentHook = nextCurrentHook
  switch nextWorkInProgressHook {
  | Some(hook) =>
    // A rerender: reuse what the previous pass built.
    checkKind(hook, kind)
    state.workInProgressHook = Some(hook)
    hook
  | None =>
    switch nextCurrentHook {
    | None =>
      Errors.fail(
        2,
        Common.Env.isDev
          ? "WeftCore: rendered more hooks than during the previous render. Hooks must be called unconditionally."
          : "",
      )
    | Some(current) =>
      checkKind(current, kind)
      let hook = {
        kind,
        memoizedState: current.memoizedState,
        baseState: current.baseState,
        baseQueue: current.baseQueue,
        queue: current.queue,
        next: None,
      }
      appendHook(fiber, hook)
      hook
    }
  }
}

/** The work-in-progress node for the next hook the component calls, and whether it's new. */
let nextHook = (kind: kind): (Fiber.t, hook, bool) => {
  let fiber = renderingFiber()
  switch state.mode {
  | Mount => (fiber, mountHook(fiber, kind), true)
  | Update | Rerender => (fiber, updateHook(fiber, kind), false)
  }
}

let isRenderPhaseUpdate = (fiber: Fiber.t): bool =>
  switch state.fiber {
  | Some(rendering) =>
    rendering === fiber ||
      switch fiber.alternate {
      | Some(alternate) => alternate === rendering
      | None => false
      }
  | None => false
  }

let maxRerenders = 25

/**
Calls `component` with `props` as the work-in-progress fiber `workInProgress`, returning what it
rendered. `current` is the fiber on screen, if any.
*/
let renderWithHooks = (
  current: option<Fiber.t>,
  workInProgress: Fiber.t,
  component: unknown => Element.t,
  props: unknown,
  renderLanes: Lanes.t,
): Element.t => {
  let hasCurrentHooks = switch current {
  | Some(current) => Option.isSome(firstHook(current))
  | None => false
  }
  state.fiber = Some(workInProgress)
  state.renderLanes = renderLanes
  state.currentHook = None
  state.workInProgressHook = None
  state.mode = hasCurrentHooks ? Update : Mount
  workInProgress.memoizedState = Unsafe.nothing
  workInProgress.updateQueue = Unsafe.nothing
  workInProgress.dependencies = None

  let children = ref(component(props))
  let rerenders = ref(0)
  while state.didScheduleRenderPhaseUpdate {
    rerenders := rerenders.contents + 1
    if rerenders.contents > maxRerenders {
      Errors.fail(
        4,
        Common.Env.isDev
          ? "WeftCore: too many re-renders. A component is setting its own state on every render."
          : "",
      )
    }
    state.didScheduleRenderPhaseUpdate = false
    state.currentHook = None
    state.workInProgressHook = None
    state.mode = Rerender
    workInProgress.updateQueue = Unsafe.nothing
    workInProgress.dependencies = None
    children := component(props)
  }

  let didRenderTooFewHooks = switch state.currentHook {
  | Some(hook) => Option.isSome(hook.next)
  | None => hasCurrentHooks
  }
  reset()
  if didRenderTooFewHooks {
    Errors.fail(
      3,
      Common.Env.isDev
        ? "WeftCore: rendered fewer hooks than during the previous render. Hooks must be called unconditionally."
        : "",
    )
  }
  children.contents
}

/**
For a component that rendered the same as last time: keep its committed effects (none of them is
due) and leave its lanes as handled.
*/
let bailoutHooks = (current: Fiber.t, workInProgress: Fiber.t, renderLanes: Lanes.t) => {
  workInProgress.updateQueue = current.updateQueue
  Fiber.removeFlag(workInProgress, Int.bitwiseOr(Fiber.Flags.passive, Fiber.Flags.layout))
  current.lanes = Lanes.remove(current.lanes, renderLanes)
}

// State and reducers

type update<'state, 'action> = {
  lane: Lanes.t,
  action: 'action,
  mutable hasEagerState: bool,
  mutable eagerState: 'state,
}

type queue<'state, 'action> = {
  /** Updates not yet seen by a render. A render moves them to the hook's `baseQueue`. */
  mutable pending: array<update<'state, 'action>>,
  mutable lastRenderedState: 'state,
  mutable lastRenderedReducer: ('state, 'action) => 'state,
  mutable dispatch: 'action => unit,
}

external queueToUnknown: queue<'state, 'action> => unknown = "%identity"
external unknownToQueue: unknown => queue<'state, 'action> = "%identity"
external updatesToUnknown: array<update<'state, 'action>> => unknown = "%identity"
external unknownToUpdates: unknown => Nullable.t<array<update<'state, 'action>>> = "%identity"

let updatesOf = (hook: hook): array<update<'state, 'action>> =>
  unknownToUpdates(hook.baseQueue)->Nullable.toOption->Option.getOr([])

let dispatch = (fiber: Fiber.t, queue: queue<'state, 'action>, ~eager: bool, action: 'action) =>
  if isRenderPhaseUpdate(fiber) {
    state.didScheduleRenderPhaseUpdate = true
    queue.pending->Array.push({
      lane: Lanes.none,
      action,
      hasEagerState: false,
      eagerState: Unsafe.fromUnknown(Unsafe.nothing),
    })
  } else {
    let update = {
      lane: updateLane.contents,
      action,
      hasEagerState: false,
      eagerState: Unsafe.fromUnknown(Unsafe.nothing),
    }
    let idle =
      eager &&
      fiber.lanes == Lanes.none &&
      switch fiber.alternate {
      | Some(alternate) => alternate.lanes == Lanes.none
      | None => true
      }
    // With nothing else pending, the new state can be computed now; if it's unchanged, there's
    // nothing to render.
    let unchanged = if idle {
      let current = queue.lastRenderedState
      let next = queue.lastRenderedReducer(current, action)
      update.hasEagerState = true
      update.eagerState = next
      Object.is(next, current)
    } else {
      false
    }
    if !unchanged {
      queue.pending->Array.push(update)
      FiberRoot.scheduleUpdate(fiber, update.lane)
    }
  }

let apply = (reducer, state: 'state, update: update<'state, 'action>) =>
  update.hasEagerState ? update.eagerState : reducer(state, update.action)

/**
Applies the updates in `renderLanes` to the base state, in order. An update in another lane is
skipped, and stays in the base queue with everything after it, so that a later render can apply them
all in their original order on top of the state before the first skipped one. (An update kept only
because it follows a skipped one gets no lane, so every later render includes it.)
*/
let processUpdates = (fiber: Fiber.t, hook: hook, reducer: ('state, 'action) => 'state): 'state => {
  let result = ref((Unsafe.fromUnknown(hook.baseState): 'state))
  let newBaseState = ref(result.contents)
  let newBaseQueue = []
  updatesOf(hook)->Array.forEach((update: update<'state, 'action>) =>
    if Lanes.isSubset(state.renderLanes, update.lane) {
      if Array.length(newBaseQueue) > 0 {
        newBaseQueue->Array.push({...update, lane: Lanes.none})
      }
      result := apply(reducer, result.contents, update)
    } else {
      if Array.length(newBaseQueue) == 0 {
        newBaseState := result.contents
      }
      newBaseQueue->Array.push(update)
      fiber.lanes = Lanes.merge(fiber.lanes, update.lane)
    }
  )
  if Array.length(newBaseQueue) == 0 {
    newBaseState := result.contents
  }
  hook.baseState = Unsafe.toUnknown(newBaseState.contents)
  hook.baseQueue = updatesToUnknown(newBaseQueue)
  result.contents
}

let useReducerWith = (
  ~kind: kind,
  ~eager: bool,
  reducer: ('state, 'action) => 'state,
  init: unit => 'state,
): ('state, 'action => unit) => {
  let (fiber, hook, isNew) = nextHook(kind)
  if isNew {
    let initial = init()
    hook.memoizedState = Unsafe.toUnknown(initial)
    hook.baseState = Unsafe.toUnknown(initial)
    hook.baseQueue = updatesToUnknown([])
    let queue = {
      pending: [],
      lastRenderedState: initial,
      lastRenderedReducer: reducer,
      dispatch: _ => (),
    }
    queue.dispatch = action => dispatch(fiber, queue, ~eager, action)
    hook.queue = queueToUnknown(queue)
    (initial, queue.dispatch)
  } else {
    let queue: queue<'state, 'action> = unknownToQueue(hook.queue)
    let previous: 'state = Unsafe.fromUnknown(hook.memoizedState)
    let next = switch state.mode {
    | Rerender =>
      // Updates made while rendering: apply them all, now.
      let next =
        queue.pending->Array.reduce(previous, (state, update) => apply(reducer, state, update))
      queue.pending = []
      if Array.length(updatesOf(hook)) == 0 {
        hook.baseState = Unsafe.toUnknown(next)
      }
      next
    | Mount | Update =>
      if Array.length(queue.pending) > 0 {
        // Moved onto the current hook too, so they survive if this render is thrown away.
        let merged = Array.concat(updatesOf(hook), queue.pending)
        queue.pending = []
        hook.baseQueue = updatesToUnknown(merged)
        state.currentHook->Option.forEach(current => current.baseQueue = updatesToUnknown(merged))
      }
      processUpdates(fiber, hook, reducer)
    }
    if !Object.is(next, previous) {
      state.didReceiveUpdate = true
    }
    hook.memoizedState = Unsafe.toUnknown(next)
    queue.lastRenderedState = next
    queue.lastRenderedReducer = reducer
    (next, queue.dispatch)
  }
}

/** Runs `f` with updates in `lane`. */
let withLane = (lane: Lanes.t, f: unit => 'a): 'a => {
  let previous = updateLane.contents
  updateLane := lane
  let result = try f() catch {
  | error =>
    updateLane := previous
    throw(error)
  }
  updateLane := previous
  result
}

/**
The previous value while an urgent render is in progress (and a transition scheduled to render the
new one), the new value otherwise.
*/
let useDeferredValue = (value: 'value): 'value => {
  let (fiber, hook, isNew) = nextHook(Deferred)
  if isNew {
    hook.memoizedState = Unsafe.toUnknown(value)
    value
  } else {
    let previous: 'value = Unsafe.fromUnknown(hook.memoizedState)
    if Object.is(previous, value) {
      value
    } else if !Lanes.isBlocking(state.renderLanes) {
      hook.memoizedState = Unsafe.toUnknown(value)
      state.didReceiveUpdate = true
      value
    } else {
      FiberRoot.scheduleUpdate(fiber, Lanes.transition)
      previous
    }
  }
}

// External stores: what this render read, to check nothing changed before it commits.

let storeChecks: array<unit => bool> = []

/** Records a store read: `isUnchanged` says whether the store still has what was read. */
let recordStoreRead = (isUnchanged: unit => bool) => storeChecks->Array.push(isUnchanged)

let storesUnchanged = () => storeChecks->Array.every(isUnchanged => isUnchanged())

let clearStoreReads = () =>
  storeChecks->Array.splice(~start=0, ~remove=Array.length(storeChecks), ~insert=[])

// Client components on the server

/**
Whether a server renderer is calling a client component (`ServerRender.renderComponent`): hooks
work, as on a first render that never commits, and `useSyncExternalStore` reads its server snapshot.
*/
let renderingForServer = ref(false)

/**
Calls `component` with `props` as the mount of a fiber that's in no tree: its hooks give their
initial state, its effects are recorded but never run (nothing commits), and an update it makes
later reaches no root and is dropped. Whatever render was in progress (a client render, or a server
component's `renderOnServer`) is set aside and restored however the call ends, with the store reads
this call recorded cleared, since only a commit checks them.
*/
let renderForServer = (component: unknown => Element.t, props: unknown): Element.t => {
  let saved = {...state, fiber: state.fiber}
  let wasOnServer = onServer.contents
  let wasForServer = renderingForServer.contents
  let savedChecks = storeChecks->Array.copy
  onServer := false
  renderingForServer := true
  let restore = () => {
    state.fiber = saved.fiber
    state.currentHook = saved.currentHook
    state.workInProgressHook = saved.workInProgressHook
    state.mode = saved.mode
    state.didScheduleRenderPhaseUpdate = saved.didScheduleRenderPhaseUpdate
    state.didReceiveUpdate = saved.didReceiveUpdate
    state.renderLanes = saved.renderLanes
    onServer := wasOnServer
    renderingForServer := wasForServer
    clearStoreReads()
    savedChecks->Array.forEach(check => storeChecks->Array.push(check))
  }
  let fiber = Fiber.make(~tag=FunctionComponent, ~key=Nullable.null, ~pendingProps=props)
  switch renderWithHooks(None, fiber, component, props, Lanes.defaultLane) {
  | element =>
    restore()
    element
  // A JS error is rethrown as itself, not wrapped in `JsExn`.
  | exception JsExn(thrown) =>
    restore()
    JsExn.throw(thrown)
  | exception error =>
    restore()
    throw(error)
  }
}

// Memoization

type memo<'value> = {value: 'value, deps: option<array<unknown>>}

external memoToUnknown: memo<'value> => unknown = "%identity"
external unknownToMemo: unknown => memo<'value> = "%identity"

let depsEqual = (previous: option<array<unknown>>, next: option<array<unknown>>): bool =>
  switch (previous, next) {
  | (Some(previous), Some(next)) =>
    Array.length(previous) == Array.length(next) &&
      previous->Array.everyWithIndex((value, index) =>
        Object.is(value, next->Array.getUnsafe(index))
      )
  | _ => false
  }

/** `create()`, unless `deps` are the same as last render's (`None` means "every render"). */
let useMemo = (create: unit => 'value, deps: option<array<unknown>>): 'value => {
  let (_, hook, isNew) = nextHook(Memo)
  let reuse =
    !isNew && {
      let previous: memo<'value> = unknownToMemo(hook.memoizedState)
      depsEqual(previous.deps, deps)
    }
  if reuse {
    unknownToMemo(hook.memoizedState).value
  } else {
    let value = create()
    hook.memoizedState = memoToUnknown({value, deps})
    value
  }
}

let useRef = (initial: 'value): Ref.t<'value> => {
  let (_, hook, isNew) = nextHook(Ref)
  if isNew {
    let box: Ref.t<'value> = {current: initial}
    hook.memoizedState = Unsafe.toUnknown(box)
    box
  } else {
    Unsafe.fromUnknown(hook.memoizedState)
  }
}

// Context

let useContext = (context: ContextImpl.t<'value>): 'value =>
  ContextImpl.read(renderingFiber(), context)

// Effects

type effectKind =
  | Passive
  | Layout

/** Shared by an effect's successive renders: the cleanup from the last time it ran. */
type effectInstance = {mutable destroy: option<unit => unit>}

type effect = {
  effectKind: effectKind,
  /** Whether it's due: its dependencies changed (or it's new). */
  hasEffect: bool,
  create: unit => option<unit => unit>,
  deps: option<array<unknown>>,
  inst: effectInstance,
}

external effectToUnknown: effect => unknown = "%identity"
external unknownToEffect: unknown => effect = "%identity"
external effectsToUnknown: array<effect> => unknown = "%identity"
external unknownToEffects: unknown => Nullable.t<array<effect>> = "%identity"

/** The effects a function component's last render declared, in order. */
let effectsOf = (fiber: Fiber.t): array<effect> =>
  switch Nullable.toOption(unknownToEffects(fiber.updateQueue)) {
  | Some(effects) => effects
  | None => []
  }

let useEffectWith = (
  ~effectKind: effectKind,
  create: unit => option<unit => unit>,
  deps: option<array<unknown>>,
) => {
  let (fiber, hook, isNew) = nextHook(effectKind == Passive ? Effect : LayoutEffect)
  // Compare with what's on screen (not an earlier pass of a rerender).
  let previous = isNew
    ? None
    : state.currentHook->Option.map(current => unknownToEffect(current.memoizedState))
  let (inst, hasEffect) = switch previous {
  | Some(previous) => (previous.inst, !depsEqual(previous.deps, deps))
  | None => ({destroy: None}, true)
  }
  let effect = {effectKind, hasEffect, create, deps, inst}
  hook.memoizedState = effectToUnknown(effect)
  switch Nullable.toOption(unknownToEffects(fiber.updateQueue)) {
  | Some(effects) => effects->Array.push(effect)
  | None => fiber.updateQueue = effectsToUnknown([effect])
  }
  if hasEffect {
    Fiber.addFlag(fiber, effectKind == Passive ? Fiber.Flags.passive : Fiber.Flags.layout)
  }
}

// Running effects, from the commit phase. An exception from one effect doesn't stop the others:
// the first is kept, and rethrown once the phase is over.

/**
Throws `error` again: the original JS value for a JS exception (which `catch` wraps in `JsExn`), so
callers see the error that was thrown.
*/
let rethrow = (error: exn) =>
  switch error {
  | JsExn(thrown) => JsExn.throw(thrown)
  | _ => throw(error)
  }

/** The first exception from an effect that no error boundary took. */
let commitError: ref<option<exn>> = ref(None)

/** Runs one of `weft_core`'s effects, sending an exception to its error boundary if it has one. */
let guard = (fiber: Fiber.t, f: unit => unit) =>
  try f() catch {
  | error =>
    if !ErrorBoundaryImpl.captureFromEffect(fiber, error) && Option.isNone(commitError.contents) {
      commitError := Some(error)
    }
  }

let rethrowCommitError = () =>
  switch commitError.contents {
  | Some(error) =>
    commitError := None
    rethrow(error)
  | None => ()
  }

/** Runs the cleanups of `weft_core`'s effects of `effectKind`: the due ones, or with `~all`, every one. */
let commitEffectsUnmount = (fiber: Fiber.t, ~effectKind: effectKind, ~all: bool) =>
  effectsOf(fiber)->Array.forEach(effect =>
    if effect.effectKind == effectKind && (all || effect.hasEffect) {
      switch effect.inst.destroy {
      | Some(destroy) =>
        effect.inst.destroy = None
        guard(fiber, destroy)
      | None => ()
      }
    }
  )

/** Runs `weft_core`'s due effects of `effectKind`, keeping their cleanups. */
let commitEffectsMount = (fiber: Fiber.t, ~effectKind: effectKind) =>
  effectsOf(fiber)->Array.forEach(effect =>
    if effect.effectKind == effectKind && effect.hasEffect {
      guard(fiber, () => effect.inst.destroy = effect.create())
    }
  )

// IDs

/**
What `ServerRender.renderComponent` was given for the component it's calling: the root's prefix, and
the component's position.
*/
let serverId: ref<option<(string, array<int>)>> = ref(None)

/** How many IDs components mounted on the client (not hydrating) have taken, across every root. */
let clientIds = ref(0)

let base32 = (n: int) => n->Int.toString(~radix=32)

/**
A position, compactly and unambiguously: an index below 32 as one base-32 digit (`0` to `v`), a
larger one as `w<digits>x`, and three or more zeros in a row as `y<count>x`.
*/
let encodePosition = (position: array<int>) => {
  let out = []
  let zeros = ref(0)
  let flush = () => {
    if zeros.contents >= 3 {
      out->Array.push(`y${base32(zeros.contents)}x`)
    } else {
      out->Array.push(String.repeat("0", zeros.contents))
    }
    zeros := 0
  }
  position->Array.forEach(index =>
    if index == 0 {
      zeros := zeros.contents + 1
    } else {
      flush()
      out->Array.push(index < 32 ? base32(index) : `w${base32(index)}x`)
    }
  )
  flush()
  out->Array.join("")
}

/**
`fiber`'s position in its tree: one index per level from the root down, its index among its
siblings, but a `Suspense` boundary's content is 0 and its fallback 1 (its `Offscreen` fiber, and
the fallback's fragment, aren't levels: the HTML renderer has neither). With its root.
*/
let positionOf = (fiber: Fiber.t): (array<int>, Fiber.t) => {
  let path = []
  let node = ref(fiber)
  let climbing = ref(true)
  while climbing.contents {
    let current = node.contents
    switch current.parent {
    | Some(parent) if current.tag != HostRoot =>
      path->Array.push(
        parent.tag == SuspenseComponent ? current.tag == OffscreenComponent ? 0 : 1 : current.index,
      )
      node := parent
    | _ => climbing := false
    }
  }
  (path->Array.toReversed, node.contents)
}

/** How many `useId` hooks `fiber` called before the newest. */
let idsBefore = (fiber: Fiber.t) => {
  let count = ref(0)
  let hook = ref(firstHook(fiber))
  while Option.isSome(hook.contents) {
    let current = Option.getUnsafe(hook.contents)
    if current.kind == Id {
      count := count.contents + 1
    }
    hook := current.next
  }
  count.contents - 1
}

let useId = (): string => {
  let (fiber, hook, isNew) = nextHook(Id)
  if isNew {
    let id = if renderingForServer.contents {
      let (prefix, position) = serverId.contents->Option.getOr(("w", []))
      `${prefix}-${encodePosition(position)}-${base32(idsBefore(fiber))}`
    } else if hydrating.contents {
      // Hydrating: from where it is, as the server's HTML did.
      let (position, root) = positionOf(fiber)
      `${FiberRoot.ofFiber(root).idPrefix}-${encodePosition(position)}-${base32(idsBefore(fiber))}`
    } else {
      // Mounted on the client: a position could be one a component moved away from still has (a
      // keyed list reordered), so a count instead, which no position's ID can be.
      clientIds := clientIds.contents + 1
      let (_, root) = positionOf(fiber)
      `${FiberRoot.ofFiber(root).idPrefix}-z${base32(clientIds.contents)}`
    }
    hook.memoizedState = Unsafe.toUnknown(id)
  }
  Unsafe.fromUnknown(hook.memoizedState)
}
