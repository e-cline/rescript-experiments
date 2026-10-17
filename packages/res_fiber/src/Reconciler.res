module type S = {
  type container
  type root
  let createRoot: container => root
  let render: (root, Element.t) => unit
  let unmount: root => unit
  let flushSync: (unit => 'a) => 'a
  let flushWork: unit => unit
  let flushPassiveEffects: unit => bool
  let flushAllWork: unit => unit
}

@val external queueMicrotask: (unit => unit) => unit = "queueMicrotask"
@val external setTimeout: (unit => unit, int) => unit = "setTimeout"

/** How many renders in a row one `flushWork` allows before deciding updates will never settle. */
let maxNestedRenders = 50

/** A host element's `ref` prop. */
@get
external refOf: unknown => Nullable.t<Ref.t<unknown>> = "ref"

module MakeWithScheduler = (Host: HostConfig.S, Sched: Scheduler.S): (
  S with type container = Host.container
) => {
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
  let isHostParent = (fiber: Fiber.t) =>
    fiber.tag == HostComponent || fiber.tag == HostRoot || fiber.tag == HostPortal

  let hostNode = (fiber: Fiber.t): Host.node =>
    fiber.tag == HostText
      ? Host.textToNode(toTextInstance(fiber.stateNode))
      : Host.instanceToNode(toInstance(fiber.stateNode))

  let containerOf = (root: FiberRoot.t) => toContainer(root.container)

  /** The container a root or portal fiber's children go in. */
  let containerOfParent = (fiber: Fiber.t) =>
    fiber.tag == HostPortal ? toContainer(fiber.stateNode) : containerOf(FiberRoot.ofFiber(fiber))

  /** Calls `f` on each child of `fiber`, in order. */
  let forEachChild = (fiber: Fiber.t, f: Fiber.t => unit) => {
    let child = ref(fiber.child)
    while Option.isSome(child.contents) {
      let c = Option.getUnsafe(child.contents)
      f(c)
      child := c.sibling
    }
  }

  // Render phase: completing fibers

  /** Appends the top-level host nodes of `first` and its siblings' subtrees to a new instance. */
  let rec appendAllChildren = (parent: Host.instance, first: option<Fiber.t>) => {
    let child = ref(first)
    while Option.isSome(child.contents) {
      let fiber = Option.getUnsafe(child.contents)
      if isHost(fiber) {
        Host.appendInitialChild(parent, hostNode(fiber))
      } else if fiber.tag != HostPortal {
        // A portal's children go in its own container.
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
          if refOf(current.memoizedProps) !== refOf(workInProgress.memoizedProps) {
            addFlag(workInProgress, Flags.ref)
          }
        }
      | None =>
        let instance = Host.createInstance(~tag, ~props=newProps, ~container=containerOf(root))
        appendAllChildren(instance, workInProgress.child)
        workInProgress.stateNode = Unsafe.toUnknown(instance)
        Host.finalizeInitialChildren(instance, ~tag, ~props=newProps)
        if !Nullable.isNullable(refOf(workInProgress.memoizedProps)) {
          addFlag(workInProgress, Flags.ref)
        }
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
    | ContextProvider => ContextImpl.pop()
    | OffscreenComponent =>
      switch current {
      | Some(current)
        if SuspenseImpl.isHiddenProps(current.memoizedProps) !=
          SuspenseImpl.isHiddenProps(workInProgress.memoizedProps) =>
        addFlag(workInProgress, Flags.visibility)
      | _ => ()
      }
    | HostRoot
    | FunctionComponent
    | MemoComponent
    | Fragment
    | ErrorBoundaryComponent
    | HostPortal
    | SuspenseComponent => ()
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
    forEachChild(fiber, c => {
      childLanes := Lanes.merge(childLanes.contents, Lanes.merge(c.lanes, c.childLanes))
      if !didBailout {
        subtreeFlags := Int.bitwiseOr(subtreeFlags.contents, Int.bitwiseOr(c.subtreeFlags, c.flags))
      }
      c.parent = Some(fiber)
    })
    fiber.subtreeFlags = subtreeFlags.contents

    // Updates in a hidden subtree wait until it's shown: the root doesn't render for them meanwhile.
    fiber.childLanes = fiber.tag == OffscreenComponent &&
      SuspenseImpl.isHiddenProps(fiber.memoizedProps)
      ? Lanes.none
      : childLanes.contents
  }

  // Render phase: the work loop. One render is in progress at a time, across all of this renderer's
  // roots. A concurrent render can stop between units of work and continue in a later task; a render
  // of anything else (another root, or more urgent lanes) throws it away.

  let workInProgress: ref<option<Fiber.t>> = ref(None)
  let workInProgressRoot: ref<option<FiberRoot.t>> = ref(None)
  let workInProgressRootFiber: ref<option<Fiber.t>> = ref(None)
  let workInProgressLanes = ref(Lanes.none)

  /** The fiber being begun or completed: where an exception came from. */
  let currentFiber: ref<option<Fiber.t>> = ref(None)

  let completeUnitOfWork = (root: FiberRoot.t, unit: Fiber.t) => {
    let completed = ref(unit)
    let climbing = ref(true)
    while climbing.contents {
      let fiber = completed.contents
      currentFiber := Some(fiber)
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
    currentFiber := Some(unit)
    let next = BeginWork.beginWork(unit.alternate, unit, renderLanes)
    unit.memoizedProps = unit.pendingProps
    switch next {
    | Some(child) => workInProgress := Some(child)
    | None => completeUnitOfWork(root, unit)
    }
  }

  /** Throws away the render in progress, if there is one. */
  let resetWorkInProgress = () => {
    if Option.isSome(workInProgressRoot.contents) {
      // Pops the values of providers the unfinished render was inside.
      ContextImpl.reset()
    }
    workInProgress := None
    workInProgressRoot := None
    workInProgressRootFiber := None
    workInProgressLanes := Lanes.none
    HookImpl.clearStoreReads()
  }

  let prepareFreshStack = (root: FiberRoot.t, lanes: Lanes.t) => {
    resetWorkInProgress()
    let rootFiber = Fiber.createWorkInProgress(root.current, root.current.pendingProps)
    workInProgressRoot := Some(root)
    workInProgressRootFiber := Some(rootFiber)
    workInProgressLanes := lanes
    workInProgress := Some(rootFiber)
  }

  let isRendering = (root: FiberRoot.t, lanes: Lanes.t) =>
    switch workInProgressRoot.contents {
    | Some(rendering) => rendering === root && workInProgressLanes.contents == lanes
    | None => false
    }

  /**
  For an exception from rendering `currentFiber`: if there's an error boundary above it, unwinds to
  the boundary (dropping the half-rendered fibers between, and the context values they provided)
  and renders it again showing the error. Returns whether there was one.
  */
  let renderAgainWithFallback = (boundary: Fiber.t) => {
    ContextImpl.unwindTo(boundary)
    addFlag(boundary, Flags.didCapture)
    // Forget what the abandoned children recorded; the fallback is reconciled against what's on
    // screen (`current.child`) afresh.
    removeFlag(boundary, Flags.childDeletion)
    boundary.deletions = None
    workInProgress := Some(boundary)
  }

  let noSuspenseBoundary = () =>
    try JsError.throwWithMessage(
      "ResFiber: a component suspended (Hooks.use on a promise that hasn't settled) with no <Suspense> boundary above it",
    ) catch {
    | error => error
    }

  /** Sends `error` to the nearest error boundary. Returns it if there's none. */
  let catchError = (thrower: Fiber.t, error: exn): option<exn> =>
    switch ErrorBoundaryImpl.find(thrower, ~skipCaptured=true) {
    | Some(boundary) =>
      ErrorBoundaryImpl.capture(boundary, error)
      renderAgainWithFallback(boundary)
      None
    | None => Some(error)
    }

  /** A transition's render that suspended, and the promise it waits for: it won't commit. */
  let suspendedOn: ref<option<promise<unknown>>> = ref(None)

  /**
  For an exception from rendering `currentFiber`. A suspension goes to the nearest `Suspense`
  boundary, which renders its fallback now and its children again once the promise settles; but in
  a transition, if that boundary is showing its children (or there's no boundary), the whole render
  is abandoned instead, so the screen keeps its previous state until the promise settles. An error
  goes to the nearest error boundary, which renders again showing it. Either way the half-rendered
  fibers in between are dropped, with the context values they provided. Returns the exception to
  rethrow, if no boundary took it.
  */
  let handleRenderError = (error: exn): option<exn> =>
    switch currentFiber.contents {
    | None => Some(error)
    | Some(thrower) =>
      switch error {
      | SuspenseImpl.Suspended(promise) =>
        let boundary = SuspenseImpl.find(thrower)
        let keepScreen =
          !Lanes.isBlocking(workInProgressLanes.contents) &&
          switch boundary {
          | Some(boundary) => SuspenseImpl.isShowingChildren(boundary.alternate)
          | None => true
          }
        switch boundary {
        | _ if keepScreen =>
          suspendedOn := Some(promise)
          workInProgress := None
          None
        | Some(boundary) =>
          SuspenseImpl.retryWhenSettled(boundary, promise)
          renderAgainWithFallback(boundary)
          None
        | None => catchError(thrower, noSuspenseBoundary())
        }
      | _ => catchError(thrower, error)
      }
    }

  type renderOutcome =
    | RenderCompleted
    | RenderYielded
    /** A transition's render was abandoned, to wait for the promise. */
    | RenderSuspended(promise<unknown>)

  /**
  Renders `lanes` of `root`, continuing the render in progress if it's of the same root and lanes
  (and starting afresh otherwise), until the tree is done or, `~yielding`, the scheduler says to
  yield. Returns whether the tree is done.
  */
  let renderRoot = (root: FiberRoot.t, lanes: Lanes.t, ~yielding: bool): renderOutcome => {
    if !isRendering(root, lanes) {
      prepareFreshStack(root, lanes)
    }
    while Option.isSome(workInProgress.contents) && !(yielding && Sched.shouldYield()) {
      try performUnitOfWork(root, Option.getUnsafe(workInProgress.contents), lanes) catch {
      | error =>
        HookImpl.reset()
        switch handleRenderError(error) {
        | Some(uncaught) =>
          resetWorkInProgress()
          HookImpl.rethrow(uncaught)
        | None => ()
        }
      }
    }
    switch suspendedOn.contents {
    | Some(promise) =>
      suspendedOn := None
      resetWorkInProgress()
      RenderSuspended(promise)
    | None => Option.isNone(workInProgress.contents) ? RenderCompleted : RenderYielded
    }
  }

  /** Hands over the finished tree of the render that just completed. */
  let takeFinishedWork = (): Fiber.t => {
    let finished = Option.getUnsafe(workInProgressRootFiber.contents)
    workInProgressRoot := None
    workInProgressRootFiber := None
    workInProgressLanes := Lanes.none
    HookImpl.clearStoreReads()
    finished
  }

  // Commit phase: refs

  let setRef = (props: unknown, value: unknown) =>
    switch Nullable.toOption(refOf(props)) {
    | Some(ref) => ref.current = value
    | None => ()
    }

  let attachRef = (fiber: Fiber.t) =>
    setRef(
      fiber.memoizedProps,
      Unsafe.toUnknown(Host.getPublicInstance(toInstance(fiber.stateNode))),
    )

  let detachRef = (props: unknown) => setRef(props, Unsafe.nothing)

  // Commit phase: mutation

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
          // A moving subtree isn't in position yet, and a portal's nodes are somewhere else.
          if hasFlag(node.contents.flags, Flags.placement) || node.contents.tag == HostPortal {
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
    if fiber.tag == HostPortal {
      // Its children are placed into its own container, each on its own.
      ()
    } else if isHost(fiber) {
      switch before {
      | Some(before) => insert(hostNode(fiber), before)
      | None => append(hostNode(fiber))
      }
    } else {
      forEachChild(fiber, child => insertOrAppend(child, ~before, ~insert, ~append))
    }

  let commitPlacement = (fiber: Fiber.t) => {
    let parent = getHostParentFiber(fiber)
    let before = getHostSibling(fiber)
    switch parent.tag {
    | HostRoot | HostPortal =>
      let container = containerOfParent(parent)
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

  /**
  Unmounts a deleted subtree's layout effects and refs, and removes its top-level host nodes from
  the host parent (`~remove`). Nested host nodes go with their ancestor, so below a host node
  `~remove` is `None`. Passive effects are cleaned up later, with the rest of the passive phase.
  */
  let rec commitDeletionEffects = (fiber: Fiber.t, ~remove: option<Host.node => unit>) =>
    switch fiber.tag {
    | HostComponent =>
      detachRef(fiber.memoizedProps)
      forEachChild(fiber, child => commitDeletionEffects(child, ~remove=None))
      remove->Option.forEach(remove => remove(hostNode(fiber)))
    | HostText => remove->Option.forEach(remove => remove(hostNode(fiber)))
    | FunctionComponent | MemoComponent =>
      HookImpl.commitEffectsUnmount(fiber, ~effectKind=Layout, ~all=true)
      forEachChild(fiber, child => commitDeletionEffects(child, ~remove))
    | HostPortal =>
      // Its children are in its own container.
      let container = toContainer(fiber.stateNode)
      forEachChild(fiber, child =>
        commitDeletionEffects(
          child,
          ~remove=Some(node => Host.removeChildFromContainer(container, node)),
        )
      )
    | HostRoot
    | Fragment
    | ContextProvider
    | ErrorBoundaryComponent
    | SuspenseComponent
    | OffscreenComponent =>
      forEachChild(fiber, child => commitDeletionEffects(child, ~remove))
    }

  let commitDeletion = (returnFiber: Fiber.t, deleted: Fiber.t) => {
    let hostParent = isHostParent(returnFiber) ? returnFiber : getHostParentFiber(returnFiber)
    let remove = switch hostParent.tag {
    | HostRoot | HostPortal =>
      let container = containerOfParent(hostParent)
      node => Host.removeChildFromContainer(container, node)
    | _ =>
      let instance = toInstance(hostParent.stateNode)
      node => Host.removeChild(instance, node)
    }
    commitDeletionEffects(deleted, ~remove=Some(remove))
    deleted.parent = None
    switch deleted.alternate {
    | Some(alternate) => alternate.parent = None
    | None => ()
    }
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

  /**
  Hides (or shows again) the top-level host nodes below an offscreen fiber. A portal's nodes are
  elsewhere and left alone, and a nested offscreen fiber that's hidden stays hidden.
  */
  let rec setVisibility = (fiber: Fiber.t, ~hide: bool) =>
    switch fiber.tag {
    | HostComponent =>
      hide
        ? Host.hideInstance(toInstance(fiber.stateNode))
        : Host.unhideInstance(toInstance(fiber.stateNode), ~props=toProps(fiber.memoizedProps))
    | HostText =>
      hide
        ? Host.hideTextInstance(toTextInstance(fiber.stateNode))
        : Host.unhideTextInstance(
            toTextInstance(fiber.stateNode),
            ~text=toString(fiber.memoizedProps),
          )
    | HostPortal => ()
    | OffscreenComponent if SuspenseImpl.isHiddenProps(fiber.memoizedProps) => ()
    | _ => forEachChild(fiber, child => setVisibility(child, ~hide))
    }

  let rec commitMutationEffects = (fiber: Fiber.t) => {
    // `deletions` stays set for the passive phase, which cleans up the deleted effects.
    switch fiber.deletions {
    | Some(deletions) => deletions->Array.forEach(deleted => commitDeletion(fiber, deleted))
    | None => ()
    }
    if hasFlag(fiber.subtreeFlags, Flags.mutationMask) {
      let placed = []
      forEachChild(fiber, child => {
        commitMutationEffects(child)
        if hasFlag(child.flags, Flags.placement) {
          placed->Array.push(child)
        }
      })
      // The children's own placements come last, last child first: each then finds the sibling it
      // goes before already in position, rather than searching past every other sibling that is
      // also moving (which makes reversing a list quadratic).
      for index in Array.length(placed) - 1 downto 0 {
        let child = placed->Array.getUnsafe(index)
        commitPlacement(child)
        removeFlag(child, Flags.placement)
      }
    }
    if hasFlag(fiber.flags, Flags.update) {
      commitUpdate(fiber)
    }
    if fiber.tag == OffscreenComponent && hasFlag(fiber.flags, Flags.visibility) {
      let hide = SuspenseImpl.isHiddenProps(fiber.memoizedProps)
      forEachChild(fiber, child => setVisibility(child, ~hide))
    }
    if isFunctionLike(fiber) && hasFlag(fiber.flags, Flags.layout) {
      HookImpl.commitEffectsUnmount(fiber, ~effectKind=Layout, ~all=false)
    }
    if fiber.tag == HostComponent && hasFlag(fiber.flags, Flags.ref) {
      switch fiber.alternate {
      | Some(current) => detachRef(current.memoizedProps)
      | None => ()
      }
    }
  }

  // Commit phase: layout (children before parents, with the new tree in place)

  let rec commitLayoutEffects = (fiber: Fiber.t) => {
    if hasFlag(fiber.subtreeFlags, Flags.layoutMask) {
      forEachChild(fiber, commitLayoutEffects)
    }
    if isFunctionLike(fiber) && hasFlag(fiber.flags, Flags.layout) {
      HookImpl.commitEffectsMount(fiber, ~effectKind=Layout)
    } else if fiber.tag == HostComponent && hasFlag(fiber.flags, Flags.ref) {
      attachRef(fiber)
    }
  }

  // Passive phase: after the commit, every cleanup first, then every effect

  let rec commitPassiveUnmountInsideDeletedTree = (fiber: Fiber.t) => {
    if isFunctionLike(fiber) {
      HookImpl.commitEffectsUnmount(fiber, ~effectKind=Passive, ~all=true)
    }
    forEachChild(fiber, commitPassiveUnmountInsideDeletedTree)
  }

  let rec commitPassiveUnmountEffects = (fiber: Fiber.t) => {
    switch fiber.deletions {
    | Some(deletions) =>
      deletions->Array.forEach(commitPassiveUnmountInsideDeletedTree)
      fiber.deletions = None
    | None => ()
    }
    if hasFlag(fiber.subtreeFlags, Flags.passiveMask) {
      forEachChild(fiber, commitPassiveUnmountEffects)
    }
    if isFunctionLike(fiber) && hasFlag(fiber.flags, Flags.passive) {
      HookImpl.commitEffectsUnmount(fiber, ~effectKind=Passive, ~all=false)
    }
  }

  let rec commitPassiveMountEffects = (fiber: Fiber.t) => {
    if hasFlag(fiber.subtreeFlags, Flags.passive) {
      forEachChild(fiber, commitPassiveMountEffects)
    }
    if isFunctionLike(fiber) && hasFlag(fiber.flags, Flags.passive) {
      HookImpl.commitEffectsMount(fiber, ~effectKind=Passive)
    }
  }

  /** The last commit's tree, while its passive effects haven't run. */
  let pendingPassive: ref<option<Fiber.t>> = ref(None)
  let isPassiveFlushScheduled = ref(false)

  let flushPassiveEffects = () =>
    switch pendingPassive.contents {
    | None => false
    | Some(finished) =>
      pendingPassive := None
      commitPassiveUnmountEffects(finished)
      commitPassiveMountEffects(finished)
      HookImpl.rethrowCommitError()
      true
    }

  let schedulePassiveEffects = (finished: Fiber.t) => {
    pendingPassive := Some(finished)

    // After the browser has had a chance to paint; any render first flushes them anyway.
    if !isPassiveFlushScheduled.contents {
      isPassiveFlushScheduled := true
      setTimeout(() => {
        isPassiveFlushScheduled := false
        flushPassiveEffects()->ignore
      }, 0)
    }
  }

  let commitRoot = (root: FiberRoot.t, finished: Fiber.t, lanes: Lanes.t) => {
    let container = containerOf(root)
    Host.prepareForCommit(container)
    commitMutationEffects(finished)
    Host.resetAfterCommit(container)
    root.current = finished

    // What's left: lanes this render didn't cover, and updates it skipped.
    root.pendingLanes = Lanes.merge(
      Lanes.remove(root.pendingLanes, lanes),
      Lanes.merge(finished.lanes, finished.childLanes),
    )
    if root.hasPendingElement && finished.memoizedState === Unsafe.toUnknown(root.pendingElement) {
      root.hasPendingElement = false
      root.pendingElement = Element.null
    }
    commitLayoutEffects(finished)
    if hasFlag(Int.bitwiseOr(finished.subtreeFlags, finished.flags), Flags.passiveMask) {
      schedulePassiveEffects(finished)
    }
    root.ensureScheduled()
    HookImpl.rethrowCommitError()
  }

  // Scheduling. Blocking lanes (sync and default) render in a flush: a microtask, or the end of
  // `flushSync`. Other lanes render in scheduler tasks, yielding between units of work.

  let scheduledRoots: array<FiberRoot.t> = []
  let liveRoots: array<FiberRoot.t> = []
  let isWorking = ref(false)
  let isFlushQueued = ref(false)

  external taskToUnknown: Sched.task => unknown = "%identity"
  external unknownToTask: unknown => Sched.task = "%identity"

  let cancelTask = (root: FiberRoot.t) => {
    root.callbackTask->Option.forEach(task => Sched.cancelCallback(unknownToTask(task)))
    root.callbackTask = None
    root.callbackLane = Lanes.none
  }

  let schedulerPriority = (lanes: Lanes.t): Scheduler.priority =>
    Lanes.intersects(lanes, Lanes.idle) ? Idle : Normal

  /**
  After an exception escapes a root's render or commit, the root stops trying: it renders again on
  its next update (whose render also picks up the updates still in the hooks' queues).
  */
  let abandon = (root: FiberRoot.t) => {
    root.pendingLanes = Lanes.none
    root.suspendedLanes = Lanes.none
    cancelTask(root)
  }

  let guardRoot = (root: FiberRoot.t, f: unit => unit) =>
    try f() catch {
    | error =>
      abandon(root)
      throw(error)
    }

  let checkRenderCount = (root: FiberRoot.t, renders: ref<int>) => {
    renders := renders.contents + 1
    if renders.contents > maxNestedRenders {
      abandon(root)
      JsError.throwWithMessage(
        "ResFiber: maximum update depth exceeded. A component keeps updating state while rendering or in a layout effect.",
      )
    }
  }

  /**
  Leaves `lanes` pending but out of the running until `promise` settles (or another update arrives):
  rendering them again before then would only suspend again.
  */
  let waitFor = (root: FiberRoot.t, lanes: Lanes.t, promise: promise<unknown>) => {
    root.suspendedLanes = Lanes.merge(root.suspendedLanes, lanes)
    let ping = _ => {
      root.suspendedLanes = Lanes.remove(root.suspendedLanes, lanes)
      root.ensureScheduled()
    }
    SuspenseImpl.onSettled(promise, ping, ping)
  }

  /** Renders the root's most urgent lane to completion, and commits it (unless it suspended). */
  let renderAndCommit = (root: FiberRoot.t, lanes: Lanes.t) =>
    guardRoot(root, () =>
      switch renderRoot(root, lanes, ~yielding=false) {
      | RenderSuspended(promise) => waitFor(root, lanes, promise)
      | RenderCompleted | RenderYielded => commitRoot(root, takeFinishedWork(), lanes)
      }
    )

  let rec flushWork = () =>
    if !isWorking.contents {
      isWorking := true
      let renders = ref(0)
      let working = ref(None)
      try {
        while Array.length(scheduledRoots) > 0 {
          let root = scheduledRoots->Array.shift->Option.getUnsafe
          working := Some(root)
          root.isScheduled = false
          // The previous commit's effects run before anything renders again.
          flushPassiveEffects()->ignore
          let lanes = FiberRoot.nextLanes(root)
          if Lanes.isBlocking(lanes) && !root.isUnmounted {
            checkRenderCount(root, renders)
            renderAndCommit(root, lanes)
          } else {
            ensureRootScheduled(root)
          }
        }
        isWorking := false
      } catch {
      | error =>
        isWorking := false
        // The roots this flush didn't reach, and the one that failed if it still has work (a root
        // whose render failed has dropped its own), get a flush of their own.
        working.contents->Option.forEach(ensureRootScheduled)
        if Array.length(scheduledRoots) > 0 {
          requestFlush()
        }
        throw(error)
      }
    }

  and requestFlush = () =>
    if !isWorking.contents && !isFlushQueued.contents {
      isFlushQueued := true
      queueMicrotask(() => {
        isFlushQueued := false
        flushWork()
      })
    }

  and ensureRootScheduled = (root: FiberRoot.t) =>
    if !root.isUnmounted {
      let next = FiberRoot.nextLanes(root)
      if next == Lanes.none {
        cancelTask(root)
      } else if Lanes.isBlocking(next) {
        // A concurrent render of this root will be thrown away, and scheduled again afterwards.
        cancelTask(root)
        if !root.isScheduled {
          root.isScheduled = true
          scheduledRoots->Array.push(root)
          requestFlush()
        }
      } else if root.callbackLane != next || Option.isNone(root.callbackTask) {
        cancelTask(root)
        scheduleConcurrentWork(root, next)
      }
    }

  and scheduleConcurrentWork = (root: FiberRoot.t, lanes: Lanes.t) => {
    root.callbackTask = Some(
      taskToUnknown(
        Sched.scheduleCallback(schedulerPriority(lanes), () => performConcurrentWork(root)),
      ),
    )
    root.callbackLane = lanes
  }

  /** A scheduler task: renders the root's most urgent lane until done, or until it's time to yield. */
  and performConcurrentWork = (root: FiberRoot.t) => {
    root.callbackTask = None
    root.callbackLane = Lanes.none
    let lanes = FiberRoot.nextLanes(root)
    if root.isUnmounted || lanes == Lanes.none {
      ()
    } else if Lanes.isBlocking(lanes) {
      ensureRootScheduled(root)
    } else if isPausedForAnotherRoot(root, lanes) {
      // Another root's render (at least as urgent) is partway through: let it finish first. Taking
      // over would throw it away, and if each root's task did that to the other, neither would
      // ever finish.
      scheduleConcurrentWork(root, lanes)
    } else {
      if !isRendering(root, lanes) {
        flushPassiveEffects()->ignore
      }
      guardRoot(root, () => renderConcurrent(root, lanes))
    }
  }

  and isPausedForAnotherRoot = (root: FiberRoot.t, lanes: Lanes.t) =>
    switch workInProgressRoot.contents {
    // A lower lane is more urgent.
    | Some(other) => other !== root && workInProgressLanes.contents <= lanes
    | None => false
    }

  and renderConcurrent = (root: FiberRoot.t, lanes: Lanes.t) =>
    switch renderRoot(root, lanes, ~yielding=true) {
    | RenderCompleted =>
      // A store that changed while the render was paused would leave components showing
      // different values of it: render again, without yielding.
      let outcome = if HookImpl.storesUnchanged() {
        RenderCompleted
      } else {
        prepareFreshStack(root, lanes)
        renderRoot(root, lanes, ~yielding=false)
      }
      switch outcome {
      | RenderSuspended(promise) => waitFor(root, lanes, promise)
      | RenderCompleted | RenderYielded => commitRoot(root, takeFinishedWork(), lanes)
      }
    | RenderYielded => scheduleConcurrentWork(root, lanes)
    | RenderSuspended(promise) => waitFor(root, lanes, promise)
    }

  let flushSync = (f: unit => 'a): 'a => {
    let result = HookImpl.withLane(Lanes.sync, f)
    flushWork()
    result
  }

  let maxActRenders = 1000

  let flushAllWork = () => {
    flushWork()
    let renders = ref(0)
    let next = () => liveRoots->Array.find(root => FiberRoot.nextLanes(root) != Lanes.none)
    let root = ref(next())
    while Option.isSome(root.contents) {
      let root' = Option.getUnsafe(root.contents)
      renders := renders.contents + 1
      if renders.contents > maxActRenders {
        JsError.throwWithMessage("ResFiber: updates keep scheduling more updates")
      }
      cancelTask(root')
      flushPassiveEffects()->ignore
      renderAndCommit(root', FiberRoot.nextLanes(root'))
      flushWork()
      root := next()
    }
  }

  // Roots

  let createRoot = (container: container): root => {
    let rootFiber = Fiber.make(~tag=HostRoot, ~key=Nullable.null, ~pendingProps=Unsafe.nothing)
    rootFiber.memoizedState = Unsafe.toUnknown(Element.null)
    let root: FiberRoot.t = {
      container: Unsafe.toUnknown(container),
      current: rootFiber,
      pendingLanes: Lanes.none,
      suspendedLanes: Lanes.none,
      pendingElement: Element.null,
      hasPendingElement: false,
      isScheduled: false,
      callbackTask: None,
      callbackLane: Lanes.none,
      isUnmounted: false,
      ensureScheduled: () => (),
    }
    rootFiber.stateNode = Unsafe.toUnknown(root)
    root.ensureScheduled = () => ensureRootScheduled(root)
    liveRoots->Array.push(root)
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
      cancelTask(root)
      if workInProgressRoot.contents === Some(root) {
        resetWorkInProgress()
      }
      switch liveRoots->Array.indexOf(root) {
      | -1 => ()
      | index => liveRoots->Array.splice(~start=index, ~remove=1, ~insert=[])
      }
    }
}

module Make = (Host: HostConfig.S) => MakeWithScheduler(Host, Scheduler.Default)
