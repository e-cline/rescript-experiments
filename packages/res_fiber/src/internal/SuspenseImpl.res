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

type offscreenProps = {mode: string, children: Element.t}

external offscreenPropsOf: unknown => offscreenProps = "%identity"
external fromArray: array<Element.t> => Element.t = "%identity"

let hidden = "hidden"
let visible = "visible"

/** Whether an offscreen fiber's props (pending or memoized) say its children are hidden. */
let isHiddenProps = (props: unknown) => offscreenPropsOf(props).mode == hidden

let offscreen = (~mode: string, children: Element.t) =>
  Element.fromNode({
    kind: Offscreen,
    elementType: Unsafe.nothing,
    key: Nullable.make("children"),
    props: Unsafe.toUnknown({mode, children}),
  })

let fallbackFragment = (fallback: Element.t) =>
  Element.fromNode({
    kind: Fragment,
    elementType: Unsafe.nothing,
    key: Nullable.make("fallback"),
    props: Unsafe.toUnknown({"children": fallback}),
  })

/**
What the boundary renders. Normally its children, in a visible offscreen fiber. Having caught a
suspension in this render: its fallback, after the children kept hidden if they've been shown (so
their state survives), or alone if they never have. The keys keep the children's fibers and the
fallback's apart.
*/
let childrenOf = (current: option<Fiber.t>, fiber: Fiber.t): Element.t => {
  let props = propsOf(fiber.pendingProps)
  if !Fiber.hasFlag(fiber.flags, Fiber.Flags.didCapture) {
    offscreen(~mode=visible, props.children)
  } else {
    let hasShownChildren = switch current->Option.flatMap(current => current.child) {
    | Some(child) => child.tag == OffscreenComponent
    | None => false
    }
    hasShownChildren
      ? fromArray([offscreen(~mode=hidden, props.children), fallbackFragment(props.fallback)])
      : fallbackFragment(props.fallback)
  }
}
