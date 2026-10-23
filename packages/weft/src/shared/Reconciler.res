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

module type Hydratable = {
  include S
  let hydrateRoot: (~idPrefix: string=?, container, Element.t) => root
}

/** Raised while hydrating, where the client's tree and the server's content disagree. */
exception HydrationMismatch(string)

module MakeHydratableWithScheduler = (Host: HostConfig.Hydratable, Sched: Scheduler.S): (
  Hydratable with type container = Host.container
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

  /** Calls `f` on each child of `weft`, in order. */
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
      | None if hasFlag(workInProgress.flags, Flags.hydrated) =>
        // The server's node, already in place with its children: what it needs is attached.
        Host.hydrateInstance(toInstance(workInProgress.stateNode), ~tag, ~props=newProps)
        if !Nullable.isNullable(refOf(workInProgress.memoizedProps)) {
          addFlag(workInProgress, Flags.ref)
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
      | None if hasFlag(workInProgress.flags, Flags.hydrated) => ()
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

  // Hydration: rendering over the server's content, adopting its nodes. While a root's first render
  // (`hydrateRoot`), or a dehydrated boundary's retry, is hydrating, a cursor walks the content: each
  // host fiber mounting claims the cursor's node, and moves it into that node's children; when the
  // fiber completes, whatever of its children wasn't claimed is removed, and the cursor moves on to
  // its next sibling. Nothing is changed during the render: removals, patches and boundaries'
  // clearing are recorded, and done at commit.

  /** What hydrating a fiber left for its completion to do. */
  type entry =
    /** A claimed host node: what's left of its children goes, and the cursor moves past it. */
    | HostEntry({node: Host.hydratable, keepsContent: bool})
    /** A complete boundary being hydrated in place: likewise, within its markers. */
    | BoundaryEntry(Host.suspenseInstance)
    /** A dehydrated boundary hydrating on its own (a retry): hydration ends when it completes. */
    | RegionEntry(Host.suspenseInstance)
    /** Part of the tree that isn't hydrated (a portal, a boundary rendered on the client). */
    | PausedEntry({resumeAt: option<Host.hydratable>})

  type hydration = {
    mutable active: bool,
    mutable cursor: option<Host.hydratable>,
    /** Each fiber whose completion has hydration work to do, innermost last. */
    stack: array<(Fiber.t, entry)>,
    /** What to do to the host at commit: removals, text patches, boundaries cleared. */
    effects: array<unit => unit>,
  }

  let hydration = {active: false, cursor: None, stack: [], effects: []}

  /** Roots whose first render hydrates, until it commits. */
  let hydratingRoots: Set.t<FiberRoot.t> = Set.make()
  /** Roots whose hydration failed outside every boundary: their container is emptied at commit. */
  let clearedRoots: Set.t<FiberRoot.t> = Set.make()
  /** Boundaries hydration gave up on in this render (a mismatch, an error): rendered on the client. */
  let clientRendered: Map.t<Fiber.t, Host.suspenseInstance> = Map.make()
  /** Boundaries whose content suspended while hydrating: left dehydrated in this render. */
  let leftDehydrated: Map.t<Fiber.t, Host.suspenseInstance> = Map.make()

  type dehydratedState = {dehydrated: Host.suspenseInstance}
  external dehydratedToUnknown: dehydratedState => unknown = "%identity"
  @get external dehydratedOf: unknown => Nullable.t<Host.suspenseInstance> = "dehydrated"

  /** A `Suspense` fiber still showing the server's content, unhydrated: its markers. */
  let dehydratedInstance = (fiber: Fiber.t) =>
    fiber.tag == SuspenseComponent && !Unsafe.isNothing(fiber.memoizedState)
      ? dehydratedOf(fiber.memoizedState)->Nullable.toOption
      : None

  let clearArray = array => array->Array.splice(~start=0, ~remove=Array.length(array), ~insert=[])

  let resetHydration = (root: option<FiberRoot.t>) => {
    clearArray(hydration.stack)
    clearArray(hydration.effects)
    clientRendered->Map.clear
    leftDehydrated->Map.clear
    switch root {
    | Some(root) if hydratingRoots->Set.has(root) =>
      hydration.active = true
      hydration.cursor = Host.firstHydratableChildOfContainer(containerOf(root))
    | _ =>
      hydration.active = false
      hydration.cursor = None
    }
  }

  let warnHydration = message =>
    if Common.Env.isDev {
      Console.error(`Weft: the server's HTML doesn't match the client's render: ${message}`)
    }

  let describeCursor = () => hydration.cursor->Option.mapOr("nothing", Host.describeHydratable)

  /** Records the removal of `first` and every hydratable node after it, at commit. */
  let removeRest = (first: option<Host.hydratable>) => {
    let extra = []
    let node = ref(first)
    while Option.isSome(node.contents) {
      let current = Option.getUnsafe(node.contents)
      extra->Array.push(current)
      node := Host.nextHydratableSibling(current)
    }
    if Array.length(extra) > 0 {
      warnHydration(
        `the server rendered ${extra
          ->Array.map(Host.describeHydratable)
          ->Array.join(", ")} where the client renders nothing`,
      )
      hydration.effects->Array.push(() => extra->Array.forEach(Host.removeHydratable))
    }
  }

  /** Stops hydrating below `fiber` (rendered on the client), resuming at `resumeAt` once it completes. */
  let pauseHydration = (fiber: Fiber.t, ~resumeAt) => {
    hydration.stack->Array.push((fiber, PausedEntry({resumeAt: resumeAt})))
    hydration.active = false
  }

  /** Renders a boundary on the client: its server content goes, and it's placed afresh. */
  let renderBoundaryOnClient = (fiber: Fiber.t, instance) => {
    hydration.effects->Array.push(() => Host.clearSuspense(instance))
    fiber.memoizedState = Unsafe.nothing
    if hydration.active {
      pauseHydration(fiber, ~resumeAt=Host.nextHydratableAfterSuspense(instance))
      addFlag(fiber, Flags.placement)
    }
  }

  /** Leaves a boundary showing the server's content, to hydrate once `retry` is called. */
  let dehydrate = (fiber: Fiber.t, instance, ~onReady) => {
    fiber.memoizedState = dehydratedToUnknown({dehydrated: instance})
    fiber.child = None
    if onReady {
      let retry = () => FiberRoot.scheduleUpdate(fiber, Lanes.defaultLane)
      hydration.effects->Array.push(() => Host.onSuspenseReady(instance, retry))
    }
    hydration.cursor = Host.nextHydratableAfterSuspense(instance)
  }

  type beginning = Begin | Skip

  /** What hydration does as `unit` begins: claim its node, or decide it isn't rendered yet. */
  let beginHydration = (unit: Fiber.t): beginning =>
    if !hydration.active {
      switch (unit.alternate, clientRendered->Map.get(unit), dehydratedInstance(unit)) {
      // A dehydrated boundary hydration gave up on in this render: its region didn't match, or
      // an error was thrown in it. (Hydrating it began, so it no longer looks dehydrated.)
      | (Some(_), Some(instance), _) =>
        renderBoundaryOnClient(unit, instance)
        Begin
      // A dehydrated boundary rendering again: its content has arrived, it failed, or it got
      // new props first.
      | (Some(current), None, Some(instance)) =>
        // Its own retry (scheduled when its content arrived, or what it waited on settled) is
        // what hydrates it: a render passing by for an update elsewhere leaves it as it is.
        let retrying = Lanes.intersects(unit.lanes, workInProgressLanes.contents)
        switch (leftDehydrated->Map.has(unit), Host.suspenseState(instance)) {
        | (true, _) => Skip
        | (false, Complete) if current.memoizedProps === unit.pendingProps && !retrying => Skip
        | (false, Complete) if current.memoizedProps === unit.pendingProps =>
          unit.memoizedState = Unsafe.nothing
          hydration.active = true
          hydration.cursor = Host.firstHydratableInSuspense(instance)
          hydration.stack->Array.push((unit, RegionEntry(instance)))
          Begin
        | (false, Pending) if current.memoizedProps === unit.pendingProps => Skip
        | _ =>
          renderBoundaryOnClient(unit, instance)
          Begin
        }
      | _ => Begin
      }
    } else if Option.isSome(unit.alternate) {
      Begin
    } else {
      switch unit.tag {
      | HostComponent =>
        let tag = toString(unit.elementType)
        switch hydration.cursor {
        | Some(node) =>
          switch Host.asInstance(node, ~tag) {
          | Some(instance) =>
            unit.stateNode = Unsafe.toUnknown(instance)
            addFlag(unit, Flags.hydrated)
            let keepsContent = Host.keepsOwnContent(~tag)
            hydration.stack->Array.push((unit, HostEntry({node, keepsContent})))
            hydration.cursor = keepsContent ? None : Host.firstHydratableChild(instance)
            Begin
          | None => throw(HydrationMismatch(`expected <${tag}>, found ${describeCursor()}`))
          }
        | None => throw(HydrationMismatch(`expected <${tag}>, found ${describeCursor()}`))
        }
      | HostText =>
        let text = toString(unit.pendingProps)
        if text == "" {
          // The HTML can't have an empty text node: this one is made, and placed, as on a mount.
          addFlag(unit, Flags.placement)
        } else {
          switch hydration.cursor->Option.flatMap(node =>
            Host.asTextInstance(node)->Option.map(instance => (node, instance))
          ) {
          | Some((node, instance)) =>
            unit.stateNode = Unsafe.toUnknown(instance)
            addFlag(unit, Flags.hydrated)
            if !Host.textMatches(instance, ~text) {
              warnHydration(`${describeCursor()} is "${text}" on the client`)
              hydration.effects->Array.push(() =>
                Host.commitTextUpdate(instance, ~oldText="", ~newText=text)
              )
            }
            hydration.cursor = Host.nextHydratableSibling(node)
          | None =>
            throw(HydrationMismatch(`expected the text "${text}", found ${describeCursor()}`))
          }
        }
        Begin
      | SuspenseComponent =>
        switch (clientRendered->Map.get(unit), leftDehydrated->Map.get(unit)) {
        | (Some(instance), _) =>
          renderBoundaryOnClient(unit, instance)
          Begin
        | (None, Some(instance)) =>
          dehydrate(unit, instance, ~onReady=false)
          Skip
        | (None, None) =>
          switch hydration.cursor->Option.flatMap(Host.asSuspenseInstance) {
          | Some(instance) =>
            switch Host.suspenseState(instance) {
            | Complete =>
              hydration.stack->Array.push((unit, BoundaryEntry(instance)))
              hydration.cursor = Host.firstHydratableInSuspense(instance)
              Begin
            | Pending =>
              dehydrate(unit, instance, ~onReady=true)
              Skip
            | Failed =>
              renderBoundaryOnClient(unit, instance)
              Begin
            }
          | None =>
            throw(HydrationMismatch(`expected a <Suspense> boundary, found ${describeCursor()}`))
          }
        }
      | HostPortal =>
        // Its children go in its own container, which has no server content.
        pauseHydration(unit, ~resumeAt=hydration.cursor)
        Begin
      | _ => Begin
      }
    }

  /** Hydration's part of `fiber`'s completion. */
  let completeHydration = (fiber: Fiber.t) => {
    switch hydration.stack->Array.at(-1) {
    | Some((entryFiber, entry)) if entryFiber === fiber =>
      hydration.stack->Array.pop->ignore
      switch entry {
      | HostEntry({node, keepsContent}) =>
        if !keepsContent {
          removeRest(hydration.cursor)
        }
        hydration.cursor = Host.nextHydratableSibling(node)
      | BoundaryEntry(instance) =>
        removeRest(hydration.cursor)
        hydration.cursor = Host.nextHydratableAfterSuspense(instance)
      | RegionEntry(_) =>
        removeRest(hydration.cursor)
        hydration.active = false
        hydration.cursor = None
      | PausedEntry({resumeAt}) =>
        hydration.active = true
        hydration.cursor = resumeAt
      }
    | _ => ()
    }
    if fiber.tag == HostRoot && hydration.active {
      removeRest(hydration.cursor)
      hydration.active = false
      hydration.cursor = None
    }
  }

  /**
  The boundary being hydrated nearest above `thrower` (in place, or a dehydrated one's retry), and
  where its entry is in the stack.
  */
  let hydratingBoundary = (thrower: Fiber.t) => {
    let found = ref(None)
    let index = ref(Array.length(hydration.stack) - 1)
    while Option.isNone(found.contents) && index.contents >= 0 {
      switch hydration.stack->Array.getUnsafe(index.contents) {
      | (fiber, BoundaryEntry(instance) | RegionEntry(instance))
        if ContextImpl.isWithin(thrower, fiber) =>
        found := Some((fiber, instance, index.contents))
      | _ => ()
      }
      index := index.contents - 1
    }
    found.contents
  }

  let completeUnitOfWork = (root: FiberRoot.t, unit: Fiber.t) => {
    let completed = ref(unit)
    let climbing = ref(true)
    while climbing.contents {
      let fiber = completed.contents
      currentFiber := Some(fiber)
      completeWork(root, fiber.alternate, fiber)
      completeHydration(fiber)
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
    let next = switch beginHydration(unit) {
    | Skip => None
    | Begin =>
      HookImpl.hydrating := hydration.active
      let next = BeginWork.beginWork(unit.alternate, unit, renderLanes)
      HookImpl.hydrating := false
      if hydration.active {
        // Its children's nodes are the server's, already in place: nothing to insert.
        forEachChild(unit, child => removeFlag(child, Flags.placement))
      }
      next
    }
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
    resetHydration(None)
  }

  let prepareFreshStack = (root: FiberRoot.t, lanes: Lanes.t) => {
    resetWorkInProgress()
    resetHydration(Some(root))
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
    try Errors.fail(
      8,
      Common.Env.isDev
        ? "Weft: a component suspended (Hooks.use on a promise that hasn't settled) with no <Suspense> boundary above it"
        : "",
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
  For an exception from rendering `thrower` while hydrating. A suspension in a boundary being
  hydrated leaves that boundary as the server rendered it (dehydrated), to try again when the
  promise settles: the server's content stays, never the client's fallback over it. A mismatch, or
  any other error, gives up on hydrating that boundary: it's rendered on the client from scratch
  (where an error happens again, for an error boundary to catch). With no boundary being hydrated
  above, a suspension waits as in any transition (hydration renders in one), and anything else
  renders the whole root on the client.
  */
  let handleHydrationError = (thrower: Fiber.t, error: exn): option<option<exn>> =>
    switch hydratingBoundary(thrower) {
    | Some((boundary, instance, index)) =>
      hydration.stack->Array.splice(
        ~start=index,
        ~remove=Array.length(hydration.stack) - index,
        ~insert=[],
      )
      ContextImpl.unwindTo(boundary)
      removeFlag(boundary, Flags.childDeletion)
      boundary.deletions = None
      boundary.child = boundary.alternate->Option.flatMap(current => current.child)
      // A retry's boundary used up its update when it began: rendered on the client, it needs one
      // again, or it would bail out, unchanged, when it begins again.
      let renderOnClient = () => {
        clientRendered->Map.set(boundary, instance)
        boundary.lanes = Lanes.merge(boundary.lanes, workInProgressLanes.contents)
      }
      switch error {
      | SuspenseImpl.Suspended(promise) =>
        leftDehydrated->Map.set(boundary, instance)
        SuspenseImpl.retryWhenSettled(boundary, promise)
      | HydrationMismatch(message) =>
        warnHydration(`${message}. The boundary is rendered on the client instead.`)
        renderOnClient()
      | _ => renderOnClient()
      }

      // The boundary begins again, and goes the way just decided (which sets the cursor). A retry's
      // boundary is outside the region it was hydrating.
      hydration.active = Option.isNone(boundary.alternate)
      hydration.cursor = None
      workInProgress := Some(boundary)
      Some(None)
    | None =>
      switch error {
      | SuspenseImpl.Suspended(_) => None
      | _ =>
        switch workInProgressRoot.contents {
        | Some(root) =>
          switch error {
          | HydrationMismatch(message) =>
            warnHydration(`${message}. The page is rendered on the client instead.`)
          | _ => ()
          }
          hydratingRoots->Set.delete(root)->ignore
          clearedRoots->Set.add(root)
          prepareFreshStack(root, workInProgressLanes.contents)
          Some(None)
        | None => None
        }
      }
    }

  /**
  Whether `fiber` is being hydrated in this render: it's new, in the hydrating root or a dehydrated
  boundary's region, and in no part of it rendered on the client.
  */
  let beingHydrated = (fiber: Fiber.t) => {
    let inRegion = hydration.stack->Array.some(((entryFiber, entry)) =>
      switch entry {
      | RegionEntry(_) => ContextImpl.isWithin(fiber, entryFiber)
      | _ => false
      }
    )
    let inClientPart = hydration.stack->Array.some(((entryFiber, entry)) =>
      switch entry {
      | PausedEntry(_) => ContextImpl.isWithin(fiber, entryFiber)
      | _ => false
      }
    )
    Option.isNone(fiber.alternate) &&
    !inClientPart &&
    (inRegion ||
    workInProgressRoot.contents->Option.mapOr(false, root => hydratingRoots->Set.has(root)))
  }

  /**
  For an exception from rendering `thrower`. A suspension goes to the nearest `Suspense`
  boundary, which renders its fallback now and its children again once the promise settles; but in
  a transition, if that boundary is showing its children (or there's no boundary), the whole render
  is abandoned instead, so the screen keeps its previous state until the promise settles. An error
  goes to the nearest error boundary, which renders again showing it. Either way the half-rendered
  fibers in between are dropped, with the context values they provided. Returns the exception to
  rethrow, if no boundary took it.
  */
  let handleOrdinaryError = (thrower: Fiber.t, error: exn): option<exn> =>
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
    | _ =>
      switch ErrorBoundaryImpl.find(thrower, ~skipCaptured=true) {
      // Thrown in a part rendered on the client (a boundary that failed on the server, say), to an
      // error boundary that's being hydrated: its fallback would have to replace server content it
      // can't tell the extent of. So hydration gives up on the boundary around the error boundary
      // (or the root), as for an error while hydrating, and the error is thrown again there.
      | Some(errorBoundary) if beingHydrated(errorBoundary) =>
        switch handleHydrationError(errorBoundary, error) {
        | Some(outcome) => outcome
        | None => catchError(thrower, error)
        }
      | _ => catchError(thrower, error)
      }
    }

  let handleRenderError = (error: exn): option<exn> =>
    switch currentFiber.contents {
    | None => Some(error)
    | Some(thrower) if hydration.active =>
      switch handleHydrationError(thrower, error) {
      | Some(outcome) => outcome
      | None => handleOrdinaryError(thrower, error)
      }
    | Some(thrower) => handleOrdinaryError(thrower, error)
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
      | None => Errors.fail(9, Common.Env.isDev ? "Weft: a host node has no host parent" : "")
      }
    }
    Option.getUnsafe(found.contents)
  }

  /**
  The host node that `weft`'s nodes go in front of: the first host node after it, in the same host
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
          } else if Option.isSome(dehydratedInstance(node.contents)) {
            // A dehydrated boundary's server content is in position: what goes before it goes
            // before its start marker.
            result := dehydratedInstance(node.contents)->Option.map(Host.suspenseInstanceToNode)
            descending := false
            searching := false
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
    | SuspenseComponent if Option.isSome(dehydratedInstance(fiber)) =>
      // No fibers below: its content is still the server's, between its markers.
      dehydratedInstance(fiber)->Option.forEach(Host.clearSuspense)
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

    // What hydrating found to remove or patch, before anything is inserted.
    if clearedRoots->Set.delete(root) {
      Host.clearContainer(container)
    }
    let effects = hydration.effects->Array.copy
    clearArray(hydration.effects)
    effects->Array.forEach(effect => effect())
    hydratingRoots->Set.delete(root)->ignore
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
      Errors.fail(
        5,
        Common.Env.isDev
          ? "Weft: maximum update depth exceeded. A component keeps updating state while rendering or in a layout effect."
          : "",
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
        Errors.fail(6, Common.Env.isDev ? "Weft: updates keep scheduling more updates" : "")
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
      idPrefix: "w",
      ensureScheduled: () => (),
    }
    rootFiber.stateNode = Unsafe.toUnknown(root)
    root.ensureScheduled = () => ensureRootScheduled(root)
    liveRoots->Array.push(root)
    root
  }

  let hydrateRoot = (~idPrefix="w", container: container, element: Element.t): root => {
    let root = createRoot(container)
    root.idPrefix = idPrefix
    hydratingRoots->Set.add(root)
    root.pendingElement = element
    root.hasPendingElement = true
    // In a transition: what suspends outside every boundary waits, with the server's content on
    // screen.
    FiberRoot.scheduleUpdate(root.current, Lanes.transition)
    root
  }

  let render = (root: root, element: Element.t) => {
    if root.isUnmounted {
      Errors.fail(7, Common.Env.isDev ? "Weft: can't render into a root that was unmounted" : "")
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

/** A host that can't hydrate, as one that never has anything to hydrate. */
module NoHydration = (Host: HostConfig.S) => {
  include Host
  type hydratable
  type suspenseInstance
  let firstHydratableChildOfContainer = (_: container) => None
  let firstHydratableChild = (_: instance) => None
  let nextHydratableSibling = (_: hydratable) => None
  let asInstance = (_: hydratable, ~tag as _) => None
  let asTextInstance = (_: hydratable) => None
  let asSuspenseInstance = (_: hydratable) => None
  let keepsOwnContent = (~tag as _) => false
  let hydrateInstance = (_: instance, ~tag as _, ~props as _) => ()
  let textMatches = (_: textInstance, ~text as _) => true
  let suspenseState = (_: suspenseInstance): HostConfig.suspenseState => Complete
  let firstHydratableInSuspense = (_: suspenseInstance) => None
  let nextHydratableAfterSuspense = (_: suspenseInstance) => None
  external suspenseInstanceToNode: suspenseInstance => node = "%identity"
  let onSuspenseReady = (_: suspenseInstance, _) => ()
  let clearSuspense = (_: suspenseInstance) => ()
  let removeHydratable = (_: hydratable) => ()
  let clearContainer = (_: container) => ()
  let describeHydratable = (_: hydratable) => ""
}

module MakeWithScheduler = (Host: HostConfig.S, Sched: Scheduler.S): (
  S with type container = Host.container
) => MakeHydratableWithScheduler(NoHydration(Host), Sched)

module Make = (Host: HostConfig.S) => MakeWithScheduler(Host, Scheduler.Default)

module MakeHydratable = (Host: HostConfig.Hydratable) => MakeHydratableWithScheduler(
  Host,
  Scheduler.Default,
)
