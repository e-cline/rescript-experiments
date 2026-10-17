/***
The reconciler, for one host: `Reconciler.Make(Host)` is a renderer's whole API for rendering.

Rendering works like React's: an update marks the fiber it was made on, and the root is scheduled.
A render walks the tree from the root, skipping subtrees with nothing to do, and builds a
work-in-progress tree; the commit phase then applies the changes it recorded to the host, all at
once. Updates are batched: every update made in the same task renders once, in a microtask, unless
`flushSync` renders it sooner.

An exception thrown while rendering leaves what's on screen as it was and propagates out of whatever
started the render (`flushSync`, `flushWork`, or the microtask). Updates that render was processing
are lost.
*/

module type S = {
  type container
  /** A tree rendered into a container. */
  type root

  /** A root for `container`, rendering nothing yet. */
  let createRoot: container => root

  /**
  Renders `element` into the root, replacing whatever it rendered before. Like any update, this is
  batched: it happens in a microtask, or at the end of an enclosing `flushSync`.
  */
  let render: (root, Element.t) => unit

  /** Removes everything the root rendered, at once. The root can't render again. */
  let unmount: root => unit

  /** Calls `f`, then renders every update it (or anything before it) made, before returning. */
  let flushSync: (unit => 'a) => 'a

  /** Renders every pending update now. */
  let flushWork: unit => unit
}

module Make: (Host: HostConfig.S) => (S with type container = Host.container)
