/***
A mounted tree: the container it renders into and its current `HostRoot` fiber (whose `stateNode` is
this record). Updates find their way here by walking up from the fiber they were made on.
*/

type t = {
  @as("con") container: unknown,
  @as("cur") mutable current: Fiber.t,
  /** Lanes with work to do somewhere in the tree. */
  @as("pl") mutable pendingLanes: Lanes.t,
  /**
  Pending lanes whose render suspended (a transition waiting for a promise, keeping the screen as it
  was): not rendered again until the promise settles or another update arrives.
  */
  @as("sl") mutable suspendedLanes: Lanes.t,
  /** The element passed to the latest `render`, until a commit has rendered it. */
  @as("pe") mutable pendingElement: Element.t,
  @as("hpe") mutable hasPendingElement: bool,
  /** Whether it's queued for blocking (sync or default) work in the next flush. */
  @as("sch") mutable isScheduled: bool,
  /** The scheduler task that will render its concurrent work, and the lane it renders. */
  @as("task") mutable callbackTask: option<unknown>,
  @as("tl") mutable callbackLane: Lanes.t,
  @as("um") mutable isUnmounted: bool,
  /** Set by the renderer that created the root: arranges for its pending lanes to be rendered. */
  @as("es") mutable ensureScheduled: unit => unit,
}

external ofStateNode: unknown => t = "%identity"

/** The lane to render next: the most urgent pending one that isn't waiting on a promise. */
let nextLanes = (root: t): Lanes.t =>
  Lanes.highestPriority(Lanes.remove(root.pendingLanes, root.suspendedLanes))

/** The root a `HostRoot` fiber belongs to. */
let ofFiber = (fiber: Fiber.t): t => ofStateNode(fiber.stateNode)

let markLanes = (fiber: Fiber.t, lane: Lanes.t) => {
  fiber.lanes = Lanes.merge(fiber.lanes, lane)
  switch fiber.alternate {
  | Some(alternate) => alternate.lanes = Lanes.merge(alternate.lanes, lane)
  | None => ()
  }
}

let markChildLanes = (fiber: Fiber.t, lane: Lanes.t) => {
  fiber.childLanes = Lanes.merge(fiber.childLanes, lane)
  switch fiber.alternate {
  | Some(alternate) => alternate.childLanes = Lanes.merge(alternate.childLanes, lane)
  | None => ()
  }
}

/**
Records an update with priority `lane` on `fiber`, marks the path up to its root (in both trees,
since either may be the one rendered next), and schedules the root. An update on a fiber that has
been removed from the tree reaches no root and is ignored.
*/
let scheduleUpdate = (fiber: Fiber.t, lane: Lanes.t) => {
  markLanes(fiber, lane)
  let node = ref(fiber)
  while Option.isSome(node.contents.parent) {
    let parent = Option.getUnsafe(node.contents.parent)
    markChildLanes(parent, lane)
    node := parent
  }
  if node.contents.tag == HostRoot {
    let root = ofFiber(node.contents)
    if !root.isUnmounted {
      root.pendingLanes = Lanes.merge(root.pendingLanes, lane)

      // A new update might be what a suspended render was waiting for: try them all again.
      root.suspendedLanes = Lanes.none
      root.ensureScheduled()
    }
  }
}
