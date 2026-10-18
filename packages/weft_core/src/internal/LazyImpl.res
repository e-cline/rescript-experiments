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

/**
What `element` stands for: itself, unless it's a lazy element, which is replaced by what its promise
resolved to (again and again, if that's a lazy too). Throws `Suspended` for a promise that hasn't
settled, and a rejected promise's error.
*/
let rec resolve = (element: Element.t): Element.t =>
  switch Element.classify(element) {
  | Node({kind: Lazy} as node) => resolve(SuspenseImpl.use(promiseOf(node)))
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
