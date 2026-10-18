/***
Error boundaries: what a boundary fiber keeps, and finding the boundary for an error.

A boundary's `stateNode` is an `instance` shared by both of its fibers (like a React class instance).
Its `memoizedState` is the `state` it rendered: the error it's showing, if any, and the `generation`
that error belongs to. `reset` bumps the instance's generation, which makes the next render drop an
error from an older one; nothing needs clearing, so a render that's thrown away can't lose a reset.
*/

type props = {
  fallback: (~error: exn, ~reset: unit => unit) => Element.t,
  children: Element.t,
}

type state = {error: option<exn>, generation: int}

type instance = {
  mutable generation: int,
  /** An error from an effect, waiting for the boundary's next render to show it. */
  mutable pendingError: option<exn>,
  mutable reset: unit => unit,
}

external propsOf: unknown => props = "%identity"
external instanceToUnknown: instance => unknown = "%identity"
external unknownToInstance: unknown => instance = "%identity"
external stateToUnknown: state => unknown = "%identity"
external unknownToState: unknown => Nullable.t<state> = "%identity"

/** The boundary's instance, created on its first render. */
let instanceOf = (fiber: Fiber.t): instance =>
  if Unsafe.isNothing(fiber.stateNode) {
    let instance = {generation: 0, pendingError: None, reset: () => ()}
    instance.reset = () => {
      instance.generation = instance.generation + 1
      FiberRoot.scheduleUpdate(fiber, Lanes.defaultLane)
    }
    fiber.stateNode = instanceToUnknown(instance)
    instance
  } else {
    unknownToInstance(fiber.stateNode)
  }

let stateOf = (fiber: Fiber.t, instance: instance): state =>
  switch Nullable.toOption(unknownToState(fiber.memoizedState)) {
  | Some(state) => state
  | None => {error: None, generation: instance.generation}
  }

/** Makes the boundary show `error` when it renders (again). */
let capture = (boundary: Fiber.t, error: exn) => {
  let instance = instanceOf(boundary)
  boundary.memoizedState = stateToUnknown({error: Some(error), generation: instance.generation})
}

/**
The nearest boundary above `fiber` (not `fiber` itself). With `~skipCaptured`, boundaries that
already caught an error in this render are passed over: their fallback is what threw.
*/
let find = (fiber: Fiber.t, ~skipCaptured: bool): option<Fiber.t> => {
  let node = ref(fiber.parent)
  let found = ref(None)
  while Option.isNone(found.contents) && Option.isSome(node.contents) {
    let candidate = Option.getUnsafe(node.contents)
    if (
      candidate.tag == ErrorBoundaryComponent &&
        !(skipCaptured && Fiber.hasFlag(candidate.flags, Fiber.Flags.didCapture))
    ) {
      found := Some(candidate)
    } else {
      node := candidate.parent
    }
  }
  found.contents
}

/**
For an error thrown by an effect of `fiber`: has its nearest boundary render the error, and returns
whether there was one.
*/
let captureFromEffect = (fiber: Fiber.t, error: exn): bool =>
  switch find(fiber, ~skipCaptured=false) {
  | Some(boundary) =>
    instanceOf(boundary).pendingError = Some(error)
    FiberRoot.scheduleUpdate(boundary, Lanes.sync)
    true
  | None => false
  }
