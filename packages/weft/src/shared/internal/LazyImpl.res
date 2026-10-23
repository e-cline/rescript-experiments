/***
`Lazy` elements: a promise of an element, standing in for it until it settles.

The reconciler never gives one a fiber. `resolve` replaces it with the element it resolved to,
before keys and types are compared, so a lazy and what it resolves to are interchangeable: replacing
one with the other, in either direction, keeps the fibers (and the state) below. A lazy that hasn't
settled suspends the render, through `Hooks.use`'s `Suspended`, to the nearest `Suspense` boundary.
*/

/** A lazy element for `promise`, which it starts tracking at once (see `make`). */
let make = (promise: promise<Element.t>): Element.t => {
  // Recording the outcome from the start means a promise that settles before the lazy is first
  // rendered is read synchronously then, rather than suspending once to find out.
  SuspenseImpl.track(promise)
  Element.fromNode({
    kind: Lazy,
    elementType: Unsafe.toUnknown(promise),
    key: Nullable.null,
    props: Unsafe.nothing,
  })
}

let promiseOf = (node: Element.node): promise<Element.t> => Unsafe.fromUnknown(node.elementType)

let isLazy = (element: Element.t): bool =>
  switch Element.classify(element) {
  | Node({kind: Lazy}) => true
  | _ => false
  }

type rethrowProps = {reason: unknown}

/** Throws `reason` when rendered: what a rejected lazy element is replaced with. */
let rethrow: JsxCore.component<rethrowProps> = props => JsExn.throw(props.reason)

/**
What `element` stands for: itself, unless it's a lazy element, which is replaced by what its promise
resolved to (again and again, if that's a lazy too). Throws `Suspended` for a promise that hasn't
settled.

A rejected promise's lazy is replaced by an element that throws the error when it renders, so the
error comes from the lazy's position, in a fiber of its own: every boundary above it can catch it,
the lazy's parent included (an `ErrorBoundary` whose child it is, say). Thrown from here, it would
come from the parent's render, out of the parent's reach. (React does the same.)
*/
let rec resolve = (element: Element.t): Element.t =>
  switch Element.classify(element) {
  | Node({kind: Lazy} as node) =>
    let promise = promiseOf(node)
    if SuspenseImpl.status(promise)->Nullable.toOption == Some(SuspenseImpl.rejected) {
      JsxCore.jsx(rethrow, {reason: SuspenseImpl.reason(promise)})
    } else {
      resolve(SuspenseImpl.use(promise))
    }
  | _ => element
  }

/**
`children` with every lazy element resolved: the same array if there are none (so it keeps its
identity, which the key warnings use), otherwise a copy, which keeps the original's "written out
in JSX" mark.
*/
let resolveAll = (children: array<Element.t>): array<Element.t> =>
  if children->Array.some(isLazy) {
    let resolved = children->Array.map(resolve)
    if Common.Env.isDev && KeyWarnings.isStatic(children) {
      KeyWarnings.markStatic(resolved)
    }
    resolved
  } else {
    children
  }
