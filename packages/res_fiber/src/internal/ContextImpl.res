/***
Context values during a render, and telling consumers when they change.

A context's `currentValue` is the value at the point the render has reached: a provider pushes its
value on the way down (`push`, in `beginWork`) and restores the previous one on the way back up
(`pop`, in `completeWork`). Outside a render it's the default.

When a provider renders with a new value, `propagateChange` finds every fiber below it that read
the context in its last render and marks it (and the path to it) as having work, so it renders even
if everything between bails out.
*/

type t<'value> = {
  @as("cv") mutable currentValue: 'value,
  @as("dv") defaultValue: 'value,
  /** The provider component, created once so its identity is stable. */
  @as("pr") mutable provider: unknown,
}

type providerProps<'value> = {value: 'value, children: Element.t}

external toUnknown: t<'value> => unknown = "%identity"
external fromUnknown: unknown => t<unknown> = "%identity"
external propsOf: unknown => providerProps<unknown> = "%identity"

/** Each entry is a context, the value to restore when its provider completes, and the provider. */
let stack: array<(t<unknown>, unknown, Fiber.t)> = []

let push = (context: t<unknown>, value: unknown, ~provider: Fiber.t) => {
  stack->Array.push((context, context.currentValue, provider))
  context.currentValue = value
}

let pop = () =>
  switch stack->Array.pop {
  | Some((context, previous, _)) => context.currentValue = previous
  | None => Errors.fail(10, ResCommon.Env.isDev ? "ResFiber: context stack underflow" : "")
  }

/** Whether `fiber` is `ancestor` or below it in the tree being rendered. */
let isWithin = (fiber: Fiber.t, ancestor: Fiber.t) => {
  let node = ref(Some(fiber))
  let found = ref(false)
  while !found.contents && Option.isSome(node.contents) {
    let current = Option.getUnsafe(node.contents)
    found := current === ancestor
    node := current.parent
  }
  found.contents
}

/** Pops the values of the providers within `ancestor`, whose render an error cut short. */
let unwindTo = (ancestor: Fiber.t) =>
  while (
    switch stack->Array.at(-1) {
    | Some((_, _, provider)) => isWithin(provider, ancestor)
    | None => false
    }
  ) {
    pop()
  }

/** Restores every context's value, after a render that threw partway. */
let reset = () =>
  while Array.length(stack) > 0 {
    pop()
  }

/** The context a provider fiber provides. */
let ofProvider = (fiber: Fiber.t): t<unknown> => fromUnknown(Marker.context(fiber.elementType))

/** Reads `context` for the fiber being rendered, recording that it depends on it. */
let read = (fiber: Fiber.t, context: t<'value>): 'value => {
  let value = context.currentValue
  let dependency: Fiber.dependency = {
    context: toUnknown(context),
    memoizedValue: Unsafe.toUnknown(value),
  }
  switch fiber.dependencies {
  | Some(dependencies) => dependencies->Array.push(dependency)
  | None => fiber.dependencies = Some([dependency])
  }
  value
}

/** Whether any context `fiber` read last time now has a different value. */
let hasChanged = (fiber: Fiber.t): bool =>
  switch fiber.dependencies {
  | Some(dependencies) =>
    dependencies->Array.some(dependency =>
      !Object.is(fromUnknown(dependency.context).currentValue, dependency.memoizedValue)
    )
  | None => false
  }

let dependsOn = (fiber: Fiber.t, context: t<unknown>): bool =>
  switch fiber.dependencies {
  | Some(dependencies) =>
    dependencies->Array.some(dependency => dependency.context === toUnknown(context))
  | None => false
  }

/** Marks `childLanes` from `fiber` up to (not including) `provider`. */
let markParentPath = (fiber: option<Fiber.t>, provider: Fiber.t, lanes: Lanes.t) => {
  let node = ref(fiber)
  let climbing = ref(true)
  while climbing.contents {
    switch node.contents {
    | Some(parent)
      if parent !== provider &&
        switch parent.alternate {
        | Some(alternate) => alternate !== provider
        | None => true
        } =>
      FiberRoot.markChildLanes(parent, lanes)
      node := parent.parent
    | _ => climbing := false
    }
  }
}

/**
Schedules every fiber under `provider` that depends on `context` to render in `renderLanes`. The
search stops at nested providers of the same context, whose consumers see that provider's value.
*/
let propagateChange = (provider: Fiber.t, context: t<unknown>, renderLanes: Lanes.t) => {
  let rec visit = (first: option<Fiber.t>) => {
    let child = ref(first)
    while Option.isSome(child.contents) {
      let fiber = Option.getUnsafe(child.contents)
      if dependsOn(fiber, context) {
        FiberRoot.markLanes(fiber, renderLanes)
        markParentPath(fiber.parent, provider, renderLanes)
      }
      let shadowed = fiber.tag == ContextProvider && ofProvider(fiber) === context
      if !shadowed {
        visit(fiber.child)
      }
      child := fiber.sibling
    }
  }
  visit(provider.child)
}
