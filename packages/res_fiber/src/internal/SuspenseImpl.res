/***
Suspending: `use` on a promise that hasn't settled throws `Suspended`, and the nearest `Suspense`
boundary catches it (see `Reconciler`'s `handleRenderError`), shows its fallback, and renders its
children again once the promise settles.

A render that suspends is thrown away, hook state and all, so what a promise resolved to is recorded
on the promise itself (as React does), where the next render's `use` finds it.
*/

exception Suspended(promise<unknown>)

type props = {fallback: Element.t, children: Element.t}

external propsOf: unknown => props = "%identity"
external toUnknownPromise: promise<'value> => promise<unknown> = "%identity"

@get external status: promise<'value> => Nullable.t<string> = "$$fiberStatus"
@set external setStatus: (promise<'value>, string) => unit = "$$fiberStatus"
@get external value: promise<'value> => 'value = "$$fiberValue"
@set external setValue: (promise<'value>, 'value) => unit = "$$fiberValue"
@get external reason: promise<'value> => unknown = "$$fiberReason"
@set external setReason: (promise<'value>, unknown) => unit = "$$fiberReason"

/** Calls one of the functions when `promise` settles (and so handles its rejection). */
@send
external onSettled: (promise<'value>, 'value => unit, unknown => unit) => unit = "then"

let fulfilled = "fulfilled"
let rejected = "rejected"
let pending = "pending"

/** Starts recording `promise`'s outcome on it, once. */
let track = (promise: promise<'value>) =>
  if Nullable.isNullable(status(promise)) {
    setStatus(promise, pending)
    onSettled(
      promise,
      result => {
        setStatus(promise, fulfilled)
        setValue(promise, result)
      },
      error => {
        setStatus(promise, rejected)
        setReason(promise, error)
      },
    )
  }

let use = (promise: promise<'value>): 'value =>
  switch Nullable.toOption(status(promise)) {
  | Some(status) if status == fulfilled => value(promise)
  | Some(status) if status == rejected => JsExn.throw(reason(promise))
  | _ =>
    track(promise)
    throw(Suspended(toUnknownPromise(promise)))
  }

/** The nearest suspense boundary above `fiber` that isn't already showing its fallback. */
let find = (fiber: Fiber.t): option<Fiber.t> => {
  let node = ref(fiber.parent)
  let found = ref(None)
  while Option.isNone(found.contents) && Option.isSome(node.contents) {
    let candidate = Option.getUnsafe(node.contents)
    if (
      candidate.tag == SuspenseComponent && !Fiber.hasFlag(candidate.flags, Fiber.Flags.didCapture)
    ) {
      found := Some(candidate)
    } else {
      node := candidate.parent
    }
  }
  found.contents
}

/** Renders `boundary` again once `promise` settles, to try its children again. */
let retryWhenSettled = (boundary: Fiber.t, promise: promise<unknown>) => {
  let retry = _ => FiberRoot.scheduleUpdate(boundary, Lanes.defaultLane)
  onSettled(promise, retry, retry)
}

/**
What the boundary renders: its children, or (having caught a suspension in this render) its
fallback. Each is in a keyed fragment, so switching between them never reuses one's fibers for the
other.
*/
let childrenOf = (fiber: Fiber.t): Element.t => {
  let props = propsOf(fiber.pendingProps)
  let showFallback = Fiber.hasFlag(fiber.flags, Fiber.Flags.didCapture)
  Element.fromNode({
    kind: Fragment,
    elementType: Unsafe.nothing,
    key: Nullable.make(showFallback ? "fallback" : "children"),
    props: Unsafe.toUnknown({"children": showFallback ? props.fallback : props.children}),
  })
}
