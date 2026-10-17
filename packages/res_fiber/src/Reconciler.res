module type S = {
  type container
  type root
  let createRoot: container => root
  let render: (root, Element.t) => unit
  let unmount: root => unit
  let flushSync: (unit => 'a) => 'a
  let flushWork: unit => unit
  let flushPassiveEffects: unit => bool
}

@val external queueMicrotask: (unit => unit) => unit = "queueMicrotask"
@val external setTimeout: (unit => unit, int) => unit = "setTimeout"

/** How many renders in a row one `flushWork` allows before deciding updates will never settle. */
let maxNestedRenders = 50

/** A host element's `ref` prop. */
@get
external refOf: unknown => Nullable.t<Ref.t<unknown>> = "ref"

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
    | HostRoot | FunctionComponent | MemoComponent | Fragment => ()
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
      ContextImpl.reset()
      root.pendingLanes = Lanes.merge(root.pendingLanes, renderLanes)
      throw(error)
    }
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
      forEachChild(fiber, child => insertOrAppend(child, ~before, ~insert, ~append))
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
    | HostRoot | Fragment | ContextProvider =>
      forEachChild(fiber, child => commitDeletionEffects(child, ~remove))
    }

  let commitDeletion = (returnFiber: Fiber.t, deleted: Fiber.t) => {
    let hostParent = isHostParent(returnFiber) ? returnFiber : getHostParentFiber(returnFiber)
    let remove = switch hostParent.tag {
    | HostRoot =>
      let container = containerOf(FiberRoot.ofFiber(hostParent))
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

  let rec commitMutationEffects = (fiber: Fiber.t) => {
    // `deletions` stays set for the passive phase, which cleans up the deleted effects.
    switch fiber.deletions {
    | Some(deletions) => deletions->Array.forEach(deleted => commitDeletion(fiber, deleted))
    | None => ()
    }
    if hasFlag(fiber.subtreeFlags, Flags.mutationMask) {
      forEachChild(fiber, commitMutationEffects)
    }
    if hasFlag(fiber.flags, Flags.placement) {
      commitPlacement(fiber)
      removeFlag(fiber, Flags.placement)
    }
    if hasFlag(fiber.flags, Flags.update) {
      commitUpdate(fiber)
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
    commitLayoutEffects(finished)
    if hasFlag(Int.bitwiseOr(finished.subtreeFlags, finished.flags), Flags.passiveMask) {
      schedulePassiveEffects(finished)
    }
    HookImpl.rethrowCommitError()
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
          // The previous commit's effects run before anything renders again.
          flushPassiveEffects()->ignore
          if root.pendingLanes != Lanes.none {
            renders := renders.contents + 1
            if renders.contents > maxNestedRenders {
              JsError.throwWithMessage(
                "ResFiber: maximum update depth exceeded. A component keeps updating state while rendering or in a layout effect.",
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
