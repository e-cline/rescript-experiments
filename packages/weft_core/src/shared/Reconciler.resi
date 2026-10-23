/***
The reconciler, for one host: `Reconciler.Make(Host)` is a renderer's whole API for rendering.

Rendering works like React's: an update marks the fiber it was made on with a lane (its priority),
and the root is scheduled. A render handles one lane: it walks the tree from the root, skipping
subtrees with nothing to do in that lane, and builds a work-in-progress tree; the commit phase then
applies the changes it recorded to the host, all at once.

Sync and default updates are batched: every one made in the same task renders once, in a microtask
(or at the end of `flushSync`), without stopping. Transitions (`Transition.start`) render in
scheduler tasks, yielding whenever the scheduler says the time slice is up, and continuing in the
next task. An update to a more urgent lane, or urgent work on another root, throws a paused render
away; it starts again once the urgent work is committed. Another root's transition waits for a
paused one to finish, rather than taking turns with it. Updates a render skips (lower priority) are kept, and
applied later in their original order.

After each commit, layout effects (`useLayoutEffect`) and refs run synchronously; passive effects
(`useEffect`) run later, every cleanup before any effect, children before parents. An update made in a
layout effect renders before the commit's caller regains control.

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

  /**
  Runs the last commit's `useEffect` cleanups and effects now, if they haven't run yet, returning
  whether there were any. They otherwise run in a `setTimeout` after the commit, or before the next
  render, whichever is first. Tests call this (through their renderer's `act`) to see effects
  synchronously.
  */
  let flushPassiveEffects: unit => bool

  /**
  Renders every pending update of every root now, transitions included, without yielding. For
  tests (their renderer's `act`), which want to see the end state without driving the scheduler.
  */
  let flushAllWork: unit => unit
}

/**
A renderer that can also hydrate: render over content that's already there (the server's HTML),
adopting its nodes rather than creating new ones.

`hydrateRoot(container, element)` is a root whose first render hydrates the container's content,
in a transition (what suspends outside every `Suspense` boundary waits, with the server's content
on screen), and that's an ordinary root after. While hydrating:

- each host element claims the next node if it's an instance of the same tag, each text a text
  node, each `Suspense` boundary its markers; nodes nothing claimed are removed at commit;
- a text that differs is patched, with a warning in development;
- a boundary whose content hadn't arrived when hydration reached it (the server still streaming it)
  is left as the server rendered it, dehydrated, and hydrated once it has (`onSuspenseReady`); one
  whose content suspends while hydrating is left the same way, and tried again when the promise
  settles; one that failed on the server is rendered on the client;
- a mismatch (a node missing, or another tag), or an error, gives up on the nearest boundary being
  hydrated: its server content is removed, and it's rendered on the client from scratch (where an
  error happens again, for an error boundary to catch). With no boundary above, the whole root is.
- a dehydrated boundary that gets new props before it has hydrated is rendered on the client.
*/
module type Hydratable = {
  include S
  let hydrateRoot: (container, Element.t) => root
}

/** Raised while hydrating where the client's tree and the server's content disagree. */
exception HydrationMismatch(string)

/** The hydrating reconciler for `Host`, scheduling concurrent work with `Sched`. */
module MakeHydratableWithScheduler: (Host: HostConfig.Hydratable, Sched: Scheduler.S) =>
(Hydratable with type container = Host.container)

/** `MakeHydratableWithScheduler(Host, Scheduler.Default)`. */
module MakeHydratable: (Host: HostConfig.Hydratable) =>
(Hydratable with type container = Host.container)

/** The reconciler for `Host`, scheduling concurrent work with `Sched`. */
module MakeWithScheduler: (Host: HostConfig.S, Sched: Scheduler.S) =>
(S with type container = Host.container)

/** `MakeWithScheduler(Host, Scheduler.Default)`. */
module Make: (Host: HostConfig.S) => (S with type container = Host.container)
