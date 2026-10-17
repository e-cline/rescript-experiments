/***
The machinery behind `Hooks`: which fiber is rendering, its list of hooks, and state updates.

A function component's hooks are a linked list on its fiber's `memoizedState`, in call order. On
mount each hook call appends a node. On update each call clones the next node of the current fiber's
list (so the state on screen is never mutated by a render that might not commit). A component that
sets its own state while rendering is called again straight away (a "rerender"), reusing the nodes
the previous pass built.

Each node records which hook made it, so calling hooks in a different order from one render to the
next fails with a clear message instead of reading one hook's state as another's.
*/

type kind =
  | State
  | Reducer
  | Ref
  | Memo

type rec hook = {
  kind: kind,
  mutable memoizedState: unknown,
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

let renderingFiber = (): Fiber.t =>
  switch state.fiber {
  | Some(fiber) => fiber
  | None =>
    JsError.throwWithMessage(
      "ResFiber: hooks can only be called while a function component is rendering",
    )
  }

let kindName = (kind: kind) =>
  switch kind {
  | State => "useState"
  | Reducer => "useReducer"
  | Ref => "useRef"
  | Memo => "useMemo/useCallback"
  }

let checkKind = (hook: hook, kind: kind) =>
  if hook.kind != kind {
    JsError.throwWithMessage(
      `ResFiber: hooks were called in a different order from the previous render (expected ${kindName(
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
  let hook = {kind, memoizedState: Unsafe.nothing, queue: Unsafe.nothing, next: None}
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
      JsError.throwWithMessage(
        "ResFiber: rendered more hooks than during the previous render. Hooks must be called unconditionally.",
      )
    | Some(current) =>
      checkKind(current, kind)
      let hook = {
        kind,
        memoizedState: current.memoizedState,
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

  let children = ref(component(props))
  let rerenders = ref(0)
  while state.didScheduleRenderPhaseUpdate {
    rerenders := rerenders.contents + 1
    if rerenders.contents > maxRerenders {
      JsError.throwWithMessage(
        "ResFiber: too many re-renders. A component is setting its own state on every render.",
      )
    }
    state.didScheduleRenderPhaseUpdate = false
    state.currentHook = None
    state.workInProgressHook = None
    state.mode = Rerender
    children := component(props)
  }

  let didRenderTooFewHooks = switch state.currentHook {
  | Some(hook) => Option.isSome(hook.next)
  | None => hasCurrentHooks
  }
  reset()
  if didRenderTooFewHooks {
    JsError.throwWithMessage(
      "ResFiber: rendered fewer hooks than during the previous render. Hooks must be called unconditionally.",
    )
  }
  children.contents
}

/** For a component that rendered the same as last time: leave its lanes as handled. */
let bailoutHooks = (current: Fiber.t, renderLanes: Lanes.t) =>
  current.lanes = Lanes.remove(current.lanes, renderLanes)

// State and reducers

type update<'state, 'action> = {
  action: 'action,
  mutable hasEagerState: bool,
  mutable eagerState: 'state,
}

type queue<'state, 'action> = {
  mutable pending: array<update<'state, 'action>>,
  mutable lastRenderedState: 'state,
  mutable lastRenderedReducer: ('state, 'action) => 'state,
  mutable dispatch: 'action => unit,
}

external queueToUnknown: queue<'state, 'action> => unknown = "%identity"
external unknownToQueue: unknown => queue<'state, 'action> = "%identity"

let dispatch = (fiber: Fiber.t, queue: queue<'state, 'action>, ~eager: bool, action: 'action) => {
  let update = {action, hasEagerState: false, eagerState: Unsafe.fromUnknown(Unsafe.nothing)}
  if isRenderPhaseUpdate(fiber) {
    state.didScheduleRenderPhaseUpdate = true
    queue.pending->Array.push(update)
  } else {
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
      FiberRoot.scheduleUpdate(fiber, updateLane.contents)
    }
  }
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
    let next = ref(previous)
    queue.pending->Array.forEach(update =>
      next := (update.hasEagerState ? update.eagerState : reducer(next.contents, update.action))
    )
    queue.pending = []
    if !Object.is(next.contents, previous) {
      state.didReceiveUpdate = true
    }
    hook.memoizedState = Unsafe.toUnknown(next.contents)
    queue.lastRenderedState = next.contents
    queue.lastRenderedReducer = reducer
    (next.contents, queue.dispatch)
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
