module type S = {
  type container
  type root
  let createRoot: container => root
  let render: (root, Element.t) => unit
  let unmount: root => unit
  let flushSync: (unit => 'a) => 'a
  let flushWork: unit => unit
}

@val external queueMicrotask: (unit => unit) => unit = "queueMicrotask"

/** How many renders in a row one `flushWork` allows before deciding updates will never settle. */
let maxNestedRenders = 50

module Make = (Host: HostConfig.S): (S with type container = Host.container) => {
  open Fiber

  type container = Host.container
  type root = FiberRoot.t

  external toInstance: unknown => Host.instance = "%identity"
  external toTextInstance: unknown => Host.textInstance = "%identity"
  external toContainer: unknown => Host.container = "%identity"
  external toProps: unknown => Host.props = "%identity"
  external toPayload: unknown => Host.updatePayload = "%identity"
  external toString: unknown => string = "%identity"

  let isHost = (fiber: Fiber.t) => fiber.tag == HostComponent || fiber.tag == HostText
  let isHostParent = (fiber: Fiber.t) => fiber.tag == HostComponent || fiber.tag == HostRoot

  let hostNode = (fiber: Fiber.t): Host.node =>
    fiber.tag == HostText
      ? Host.textToNode(toTextInstance(fiber.stateNode))
      : Host.instanceToNode(toInstance(fiber.stateNode))

  let containerOf = (root: FiberRoot.t) => toContainer(root.container)

  // Render phase: completing fibers

  /** Appends the top-level host nodes of `first` and its siblings' subtrees to a new instance. */
  let rec appendAllChildren = (parent: Host.instance, first: option<Fiber.t>) => {
    let child = ref(first)
    while Option.isSome(child.contents) {
      let fiber = Option.getUnsafe(child.contents)
      if isHost(fiber) {
        Host.appendInitialChild(parent, hostNode(fiber))
      } else {
        appendAllChildren(parent, fiber.child)
      }
      child := fiber.sibling
    }
  }

  let completeWork = (root: FiberRoot.t, current: option<Fiber.t>, workInProgress: Fiber.t) =>
    switch workInProgress.tag {
    | HostComponent =>
      let tag = toString(workInProgress.elementType)
      let newProps = toProps(workInProgress.memoizedProps)
      switch current {
      | Some(current) =>
        if current.memoizedProps !== workInProgress.memoizedProps {
          switch Host.prepareUpdate(
            toInstance(workInProgress.stateNode),
            ~tag,
            ~oldProps=toProps(current.memoizedProps),
            ~newProps,
          ) {
          | Some(payload) =>
            workInProgress.updateQueue = Unsafe.toUnknown(payload)
            addFlag(workInProgress, Flags.update)
          | None => ()
          }
        }
      | None =>
        let instance = Host.createInstance(~tag, ~props=newProps, ~container=containerOf(root))
        appendAllChildren(instance, workInProgress.child)
        workInProgress.stateNode = Unsafe.toUnknown(instance)
        Host.finalizeInitialChildren(instance, ~tag, ~props=newProps)
      }
    | HostText =>
      let text = toString(workInProgress.memoizedProps)
      switch current {
      | Some(current) =>
        if toString(current.memoizedProps) !== text {
          addFlag(workInProgress, Flags.update)
        }
      | None =>
        workInProgress.stateNode = Unsafe.toUnknown(
          Host.createTextInstance(text, ~container=containerOf(root)),
        )
      }
    | HostRoot | FunctionComponent | Fragment => ()
    }

  /**
  Gathers the children's lanes and flags into `childLanes` and `subtreeFlags`. When the children are
  the current tree's own (the fiber bailed out), their flags are left over from an earlier commit,
  so only lanes are gathered.
  */
  let bubbleProperties = (fiber: Fiber.t) => {
    let didBailout = switch fiber.alternate {
    | Some(current) => current.child === fiber.child
    | None => false
    }
    let subtreeFlags = ref(Flags.none)
    let childLanes = ref(Lanes.none)
    let child = ref(fiber.child)
    while Option.isSome(child.contents) {
      let c = Option.getUnsafe(child.contents)
      childLanes := Lanes.merge(childLanes.contents, Lanes.merge(c.lanes, c.childLanes))
      if !didBailout {
        subtreeFlags := Int.bitwiseOr(subtreeFlags.contents, Int.bitwiseOr(c.subtreeFlags, c.flags))
      }
      c.parent = Some(fiber)
      child := c.sibling
    }
    fiber.subtreeFlags = subtreeFlags.contents
    fiber.childLanes = childLanes.contents
  }

  // Render phase: the work loop

  let workInProgress: ref<option<Fiber.t>> = ref(None)

  let completeUnitOfWork = (root: FiberRoot.t, unit: Fiber.t) => {
    let completed = ref(unit)
    let climbing = ref(true)
    while climbing.contents {
      let fiber = completed.contents
      completeWork(root, fiber.alternate, fiber)
      bubbleProperties(fiber)
      switch (fiber.sibling, fiber.parent) {
      | (Some(sibling), _) =>
        workInProgress := Some(sibling)
        climbing := false
      | (None, Some(parent)) => completed := parent
      | (None, None) =>
        workInProgress := None
        climbing := false
      }
    }
  }

  let performUnitOfWork = (root: FiberRoot.t, unit: Fiber.t, renderLanes: Lanes.t) => {
    let next = BeginWork.beginWork(unit.alternate, unit, renderLanes)
    unit.memoizedProps = unit.pendingProps
    switch next {
    | Some(child) => workInProgress := Some(child)
    | None => completeUnitOfWork(root, unit)
    }
  }

  /** Renders the root's pending lanes to completion, returning the finished work-in-progress root. */
  let renderRoot = (root: FiberRoot.t): Fiber.t => {
    let renderLanes = root.pendingLanes
    root.pendingLanes = Lanes.none
    let finished = Fiber.createWorkInProgress(root.current, root.current.pendingProps)
    workInProgress := Some(finished)
    try {
      while Option.isSome(workInProgress.contents) {
        performUnitOfWork(root, Option.getUnsafe(workInProgress.contents), renderLanes)
      }
    } catch {
    | error =>
      workInProgress := None
      HookImpl.reset()
      root.pendingLanes = Lanes.merge(root.pendingLanes, renderLanes)
      throw(error)
    }
    finished
  }

  // Commit phase

  let getHostParentFiber = (fiber: Fiber.t): Fiber.t => {
    let parent = ref(fiber.parent)
    let found = ref(None)
    while Option.isNone(found.contents) {
      switch parent.contents {
      | Some(p) if isHostParent(p) => found := Some(p)
      | Some(p) => parent := p.parent
      | None => JsError.throwWithMessage("ResFiber: a host node has no host parent")
      }
    }
    Option.getUnsafe(found.contents)
  }

  /**
  The host node that `fiber`'s nodes go in front of: the first host node after it, in the same host
  parent, that isn't itself being placed in this commit (and so is already in position). `None` means
  append.
  */
  let getHostSibling = (fiber: Fiber.t): option<Host.node> => {
    let node = ref(fiber)
    let result = ref(None)
    let searching = ref(true)
    while searching.contents {
      // Climb until there's a sibling, without leaving the host parent.
      while searching.contents && Option.isNone(node.contents.sibling) {
        switch node.contents.parent {
        | Some(parent) if !isHostParent(parent) => node := parent
        | _ => searching := false
        }
      }
      if searching.contents {
        let sibling = Option.getUnsafe(node.contents.sibling)
        node := sibling
        // Descend to the sibling's first host node, unless that part of the tree is moving too.
        let descending = ref(true)
        while descending.contents && !isHost(node.contents) {
          if hasFlag(node.contents.flags, Flags.placement) {
            descending := false
          } else {
            switch node.contents.child {
            | Some(child) => node := child
            | None => descending := false
            }
          }
        }
        if isHost(node.contents) && !hasFlag(node.contents.flags, Flags.placement) {
          result := Some(hostNode(node.contents))
          searching := false
        }
      }
    }
    result.contents
  }

  let rec insertOrAppend = (fiber: Fiber.t, ~before: option<Host.node>, ~insert, ~append) =>
    if isHost(fiber) {
      switch before {
      | Some(before) => insert(hostNode(fiber), before)
      | None => append(hostNode(fiber))
      }
    } else {
      let child = ref(fiber.child)
      while Option.isSome(child.contents) {
        let c = Option.getUnsafe(child.contents)
        insertOrAppend(c, ~before, ~insert, ~append)
        child := c.sibling
      }
    }

  let commitPlacement = (fiber: Fiber.t) => {
    let parent = getHostParentFiber(fiber)
    let before = getHostSibling(fiber)
    switch parent.tag {
    | HostRoot =>
      let container = containerOf(FiberRoot.ofFiber(parent))
      insertOrAppend(
        fiber,
        ~before,
        ~insert=(node, before) => Host.insertInContainerBefore(container, node, ~before),
        ~append=node => Host.appendChildToContainer(container, node),
      )
    | _ =>
      let instance = toInstance(parent.stateNode)
      insertOrAppend(
        fiber,
        ~before,
        ~insert=(node, before) => Host.insertBefore(instance, node, ~before),
        ~append=node => Host.appendChild(instance, node),
      )
    }
  }

  /** Removes the top-level host nodes of `fiber`'s subtree from their host parent. */
  let rec removeHostNodes = (fiber: Fiber.t, ~remove: Host.node => unit) =>
    if isHost(fiber) {
      remove(hostNode(fiber))
    } else {
      let child = ref(fiber.child)
      while Option.isSome(child.contents) {
        let c = Option.getUnsafe(child.contents)
        removeHostNodes(c, ~remove)
        child := c.sibling
      }
    }

  let detach = (fiber: Fiber.t) => {
    fiber.parent = None
    switch fiber.alternate {
    | Some(alternate) => alternate.parent = None
    | None => ()
    }
  }

  let commitDeletion = (returnFiber: Fiber.t, deleted: Fiber.t) => {
    let hostParent = isHostParent(returnFiber) ? returnFiber : getHostParentFiber(returnFiber)
    switch hostParent.tag {
    | HostRoot =>
      let container = containerOf(FiberRoot.ofFiber(hostParent))
      removeHostNodes(deleted, ~remove=node => Host.removeChildFromContainer(container, node))
    | _ =>
      let instance = toInstance(hostParent.stateNode)
      removeHostNodes(deleted, ~remove=node => Host.removeChild(instance, node))
    }
    detach(deleted)
  }

  let commitUpdate = (fiber: Fiber.t) =>
    switch (fiber.tag, fiber.alternate) {
    | (HostComponent, Some(current)) =>
      Host.commitUpdate(
        toInstance(fiber.stateNode),
        toPayload(fiber.updateQueue),
        ~tag=toString(fiber.elementType),
        ~oldProps=toProps(current.memoizedProps),
        ~newProps=toProps(fiber.memoizedProps),
      )
      fiber.updateQueue = Unsafe.nothing
    | (HostText, Some(current)) =>
      Host.commitTextUpdate(
        toTextInstance(fiber.stateNode),
        ~oldText=toString(current.memoizedProps),
        ~newText=toString(fiber.memoizedProps),
      )
    | _ => ()
    }

  let rec commitMutationEffects = (fiber: Fiber.t) => {
    switch fiber.deletions {
    | Some(deletions) =>
      deletions->Array.forEach(deleted => commitDeletion(fiber, deleted))
      fiber.deletions = None
    | None => ()
    }
    if hasFlag(fiber.subtreeFlags, Flags.mutationMask) {
      let child = ref(fiber.child)
      while Option.isSome(child.contents) {
        let c = Option.getUnsafe(child.contents)
        commitMutationEffects(c)
        child := c.sibling
      }
    }
    if hasFlag(fiber.flags, Flags.placement) {
      commitPlacement(fiber)
      removeFlag(fiber, Flags.placement)
    }
    if hasFlag(fiber.flags, Flags.update) {
      commitUpdate(fiber)
    }
  }

  let commitRoot = (root: FiberRoot.t, finished: Fiber.t) => {
    let container = containerOf(root)
    Host.prepareForCommit(container)
    commitMutationEffects(finished)
    Host.resetAfterCommit(container)
    root.current = finished
    if root.hasPendingElement && finished.memoizedState === Unsafe.toUnknown(root.pendingElement) {
      root.hasPendingElement = false
      root.pendingElement = Element.null
    }
  }

  // Scheduling

  let scheduledRoots: array<FiberRoot.t> = []
  let isWorking = ref(false)
  let isFlushQueued = ref(false)

  let flushWork = () =>
    if !isWorking.contents {
      isWorking := true
      let renders = ref(0)
      try {
        while Array.length(scheduledRoots) > 0 {
          let root = scheduledRoots->Array.shift->Option.getUnsafe
          root.isScheduled = false
          if root.pendingLanes != Lanes.none {
            renders := renders.contents + 1
            if renders.contents > maxNestedRenders {
              JsError.throwWithMessage(
                "ResFiber: maximum update depth exceeded. A component keeps updating state while rendering.",
              )
            }
            commitRoot(root, renderRoot(root))
          }
        }
        isWorking := false
      } catch {
      | error =>
        isWorking := false
        scheduledRoots->Array.forEach(root => root.isScheduled = false)
        scheduledRoots->Array.splice(~start=0, ~remove=Array.length(scheduledRoots), ~insert=[])
        throw(error)
      }
    }

  let ensureRootScheduled = (root: FiberRoot.t) =>
    if !root.isScheduled && !root.isUnmounted {
      root.isScheduled = true
      scheduledRoots->Array.push(root)
      if !isWorking.contents && !isFlushQueued.contents {
        isFlushQueued := true
        queueMicrotask(() => {
          isFlushQueued := false
          flushWork()
        })
      }
    }

  let flushSync = (f: unit => 'a): 'a => {
    let previousLane = HookImpl.updateLane.contents
    HookImpl.updateLane := Lanes.sync
    let result = try f() catch {
    | error =>
      HookImpl.updateLane := previousLane
      throw(error)
    }
    HookImpl.updateLane := previousLane
    flushWork()
    result
  }

  // Roots

  let createRoot = (container: container): root => {
    let rootFiber = Fiber.make(~tag=HostRoot, ~key=Nullable.null, ~pendingProps=Unsafe.nothing)
    rootFiber.memoizedState = Unsafe.toUnknown(Element.null)
    let root: FiberRoot.t = {
      container: Unsafe.toUnknown(container),
      current: rootFiber,
      pendingLanes: Lanes.none,
      pendingElement: Element.null,
      hasPendingElement: false,
      isScheduled: false,
      isUnmounted: false,
      ensureScheduled: () => (),
    }
    rootFiber.stateNode = Unsafe.toUnknown(root)
    root.ensureScheduled = () => ensureRootScheduled(root)
    root
  }

  let render = (root: root, element: Element.t) => {
    if root.isUnmounted {
      JsError.throwWithMessage("ResFiber: can't render into a root that was unmounted")
    }
    root.pendingElement = element
    root.hasPendingElement = true
    FiberRoot.scheduleUpdate(root.current, HookImpl.updateLane.contents)
  }

  let unmount = (root: root) =>
    if !root.isUnmounted {
      flushSync(() => render(root, Element.null))
      root.isUnmounted = true
    }
}
