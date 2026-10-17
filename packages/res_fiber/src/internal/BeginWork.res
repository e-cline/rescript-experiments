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
  renderLanes: Lanes.t,
) => {
  let children = HookImpl.renderWithHooks(
    current,
    workInProgress,
    toComponent(workInProgress.elementType),
    workInProgress.pendingProps,
    renderLanes,
  )
  switch current {
  | Some(current) if !HookImpl.state.didReceiveUpdate =>
    HookImpl.bailoutHooks(current, renderLanes)
    bailoutOnAlreadyFinishedWork(workInProgress, renderLanes)
  | _ =>
    ChildReconciler.reconcileChildren(current, workInProgress, children)
    workInProgress.child
  }
}

let beginWork = (current: option<Fiber.t>, workInProgress: Fiber.t, renderLanes: Lanes.t): option<
  Fiber.t,
> => {
  let bailout = switch current {
  | Some(current) =>
    if current.memoizedProps !== workInProgress.pendingProps {
      HookImpl.state.didReceiveUpdate = true
      false
    } else {
      HookImpl.state.didReceiveUpdate = false
      !Lanes.intersects(workInProgress.lanes, renderLanes)
    }
  | None =>
    HookImpl.state.didReceiveUpdate = false
    false
  }
  if bailout {
    bailoutOnAlreadyFinishedWork(workInProgress, renderLanes)
  } else {
    workInProgress.lanes = Lanes.none
    switch workInProgress.tag {
    | HostRoot => updateHostRoot(current, workInProgress)
    | FunctionComponent => updateFunctionComponent(current, workInProgress, renderLanes)
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
    | HostText => None
    }
  }
}
