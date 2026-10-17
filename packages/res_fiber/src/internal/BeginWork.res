/***
The first half of a fiber's render-phase work, which doesn't involve the host: render a component,
or read a host element's or fragment's children, and reconcile the result into child fibers. Returns
the child to work on next, or `None` to complete this fiber.

A fiber whose props are unchanged and has no update of its own bails out: its children are reused
as they are if nothing below has updates either, or cloned so the work loop can reach the ones that
do.
*/

open Fiber

external toComponent: unknown => unknown => Element.t = "%identity"
external toElement: unknown => Element.t = "%identity"

let cloneChildFibers = (workInProgress: Fiber.t) =>
  switch workInProgress.child {
  | None => ()
  | Some(currentChild) =>
    let clone = (current: Fiber.t) => {
      let fiber = Fiber.createWorkInProgress(current, current.pendingProps)
      fiber.parent = Some(workInProgress)
      fiber
    }
    let newChild = clone(currentChild)
    workInProgress.child = Some(newChild)
    let current = ref(currentChild)
    let previous = ref(newChild)
    while Option.isSome(current.contents.sibling) {
      let next = Option.getUnsafe(current.contents.sibling)
      let fiber = clone(next)
      previous.contents.sibling = Some(fiber)
      current := next
      previous := fiber
    }
    previous.contents.sibling = None
  }

let bailoutOnAlreadyFinishedWork = (workInProgress: Fiber.t, renderLanes: Lanes.t): option<
  Fiber.t,
> =>
  if Lanes.intersects(workInProgress.childLanes, renderLanes) {
    cloneChildFibers(workInProgress)
    workInProgress.child
  } else {
    None
  }

let updateHostRoot = (current: option<Fiber.t>, workInProgress: Fiber.t) => {
  let root = FiberRoot.ofFiber(workInProgress)
  if root.hasPendingElement {
    workInProgress.memoizedState = Unsafe.toUnknown(root.pendingElement)
  }
  ChildReconciler.reconcileChildren(
    current,
    workInProgress,
    toElement(workInProgress.memoizedState),
  )
  workInProgress.child
}

let updateFunctionComponent = (
  current: option<Fiber.t>,
  workInProgress: Fiber.t,
  component: unknown => Element.t,
  renderLanes: Lanes.t,
) => {
  switch current {
  | Some(current) if ContextImpl.hasChanged(current) => HookImpl.state.didReceiveUpdate = true
  | _ => ()
  }
  let children = HookImpl.renderWithHooks(
    current,
    workInProgress,
    component,
    workInProgress.pendingProps,
    renderLanes,
  )
  switch current {
  | Some(current) if !HookImpl.state.didReceiveUpdate =>
    HookImpl.bailoutHooks(current, workInProgress, renderLanes)
    bailoutOnAlreadyFinishedWork(workInProgress, renderLanes)
  | _ =>
    ChildReconciler.reconcileChildren(current, workInProgress, children)
    workInProgress.child
  }
}

/**
A memoized component whose props compare equal skips rendering, unless it has an update of its own
(then it renders, but its old output is reused if its state ends up unchanged).
*/
let updateMemoComponent = (
  current: option<Fiber.t>,
  workInProgress: Fiber.t,
  ~hasUpdate: bool,
  renderLanes: Lanes.t,
) => {
  let inner = Marker.memoInner(workInProgress.elementType)
  switch current {
  | Some(current)
    if Marker.memoCompare(workInProgress.elementType)(
      current.memoizedProps,
      workInProgress.pendingProps,
    ) =>
    // Keep the old props record, so the next comparison starts from the same identity.
    workInProgress.pendingProps = current.memoizedProps
    HookImpl.state.didReceiveUpdate = false
    if hasUpdate || ContextImpl.hasChanged(current) {
      updateFunctionComponent(Some(current), workInProgress, inner, renderLanes)
    } else {
      bailoutOnAlreadyFinishedWork(workInProgress, renderLanes)
    }
  | _ => updateFunctionComponent(current, workInProgress, inner, renderLanes)
  }
}

let updateContextProvider = (current: option<Fiber.t>, workInProgress: Fiber.t, renderLanes) => {
  let context = ContextImpl.ofProvider(workInProgress)
  let props = ContextImpl.propsOf(workInProgress.pendingProps)
  ContextImpl.push(context, props.value, ~provider=workInProgress)
  let unchanged = switch current {
  | Some(current) =>
    let previous = ContextImpl.propsOf(current.memoizedProps)
    if Object.is(previous.value, props.value) {
      previous.children === props.children
    } else {
      ContextImpl.propagateChange(workInProgress, context, renderLanes)
      false
    }
  | None => false
  }
  if unchanged {
    bailoutOnAlreadyFinishedWork(workInProgress, renderLanes)
  } else {
    ChildReconciler.reconcileChildren(current, workInProgress, props.children)
    workInProgress.child
  }
}

/**
Renders the children, or the fallback while there's an error to show: one just caught (in this
render, or from an effect) or still showing from before, unless `reset` was called since.
*/
let updateErrorBoundary = (current: option<Fiber.t>, workInProgress: Fiber.t) => {
  let props = ErrorBoundaryImpl.propsOf(workInProgress.pendingProps)
  let instance = ErrorBoundaryImpl.instanceOf(workInProgress)
  let previous = ErrorBoundaryImpl.stateOf(workInProgress, instance)
  let state: ErrorBoundaryImpl.state = switch instance.pendingError {
  | Some(error) =>
    instance.pendingError = None
    {error: Some(error), generation: instance.generation}
  | None if previous.generation != instance.generation => {
      error: None,
      generation: instance.generation,
    }
  | None => previous
  }
  workInProgress.memoizedState = ErrorBoundaryImpl.stateToUnknown(state)
  let children = switch state.error {
  | Some(error) => props.fallback(~error, ~reset=instance.reset)
  | None => props.children
  }
  ChildReconciler.reconcileChildren(current, workInProgress, children)
  workInProgress.child
}

let beginWork = (current: option<Fiber.t>, workInProgress: Fiber.t, renderLanes: Lanes.t): option<
  Fiber.t,
> => {
  let hasUpdate = Lanes.intersects(workInProgress.lanes, renderLanes)
  let bailout = switch current {
  | Some(current) =>
    if current.memoizedProps !== workInProgress.pendingProps {
      HookImpl.state.didReceiveUpdate = true
      false
    } else {
      HookImpl.state.didReceiveUpdate = false
      // A boundary that just caught an error renders again whatever its props.
      !hasUpdate && !Fiber.hasFlag(workInProgress.flags, Fiber.Flags.didCapture)
    }
  | None =>
    HookImpl.state.didReceiveUpdate = false
    false
  }
  if bailout {
    // A provider still provides its value to whatever below does render (`completeWork` pops it).
    if workInProgress.tag == ContextProvider {
      ContextImpl.push(
        ContextImpl.ofProvider(workInProgress),
        ContextImpl.propsOf(workInProgress.memoizedProps).value,
        ~provider=workInProgress,
      )
    }
    bailoutOnAlreadyFinishedWork(workInProgress, renderLanes)
  } else {
    workInProgress.lanes = Lanes.none
    switch workInProgress.tag {
    | HostRoot => updateHostRoot(current, workInProgress)
    | FunctionComponent =>
      updateFunctionComponent(
        current,
        workInProgress,
        toComponent(workInProgress.elementType),
        renderLanes,
      )
    | MemoComponent => updateMemoComponent(current, workInProgress, ~hasUpdate, renderLanes)
    | ContextProvider => updateContextProvider(current, workInProgress, renderLanes)
    | HostComponent =>
      ChildReconciler.reconcileChildren(
        current,
        workInProgress,
        Element.childrenOf(workInProgress.pendingProps),
      )
      workInProgress.child
    | Fragment =>
      ChildReconciler.reconcileChildren(
        current,
        workInProgress,
        toElement(workInProgress.pendingProps),
      )
      workInProgress.child
    | ErrorBoundaryComponent => updateErrorBoundary(current, workInProgress)
    | SuspenseComponent =>
      ChildReconciler.reconcileChildren(
        current,
        workInProgress,
        SuspenseImpl.childrenOf(workInProgress),
      )
      workInProgress.child
    | HostPortal =>
      ChildReconciler.reconcilePortalChildren(
        current,
        workInProgress,
        Element.childrenOf(workInProgress.pendingProps),
      )
      workInProgress.child
    | HostText => None
    }
  }
}
