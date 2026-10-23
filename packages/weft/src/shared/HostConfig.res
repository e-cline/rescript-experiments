/***
What a renderer implements: how to create, change and arrange its nodes. `Reconciler.Make` takes one
of these and returns the functions to render into it. The reconciler decides what changes and when;
the host only carries out the operations.

Instances are built bottom-up off-screen during rendering (`createInstance`, `appendInitialChild`,
`finalizeInitialChildren`), so a new subtree is attached with a single insertion. Everything that
touches nodes already on screen happens in the commit phase, between `prepareForCommit` and
`resetAfterCommit`.
*/

module type S = {
  /** What a root renders into. */
  type container
  /** A host element's node. */
  type instance
  /** A text node. */
  type textInstance
  /** What `instance` and `textInstance` both are, for operations that take either. */
  type node
  /** Host elements' props: the renderer's `Jsx.Elements.props`. */
  type props
  /** What `prepareUpdate` works out for `commitUpdate` to apply. */
  type updatePayload
  /** What a host element's `ref` prop receives: the type in its `Jsx.Elements.props`. */
  type publicInstance

  let instanceToNode: instance => node
  let textToNode: textInstance => node
  let getPublicInstance: instance => publicInstance

  let createInstance: (~tag: string, ~props: props, ~container: container) => instance
  let createTextInstance: (string, ~container: container) => textInstance
  /** Appends a child to a new, not yet attached `instance`. */
  let appendInitialChild: (instance, node) => unit
  /** Called once a new instance has all its children, to apply the rest of its props. */
  let finalizeInitialChildren: (instance, ~tag: string, ~props: props) => unit

  /**
  Compares an instance's old and new props (which are different records). `None` means nothing on
  screen changes, and `commitUpdate` isn't called.
  */
  let prepareUpdate: (
    instance,
    ~tag: string,
    ~oldProps: props,
    ~newProps: props,
  ) => option<updatePayload>
  let commitUpdate: (
    instance,
    updatePayload,
    ~tag: string,
    ~oldProps: props,
    ~newProps: props,
  ) => unit
  let commitTextUpdate: (textInstance, ~oldText: string, ~newText: string) => unit

  /**
  Hides a node that's on screen without removing it, for content a `Suspense` boundary keeps
  mounted behind its fallback (in the DOM, `display: none`).
  */
  let hideInstance: instance => unit
  /** Shows a hidden node again, as its current `props` say. */
  let unhideInstance: (instance, ~props: props) => unit
  let hideTextInstance: textInstance => unit
  /** Shows a hidden text node again, with its current `text`. */
  let unhideTextInstance: (textInstance, ~text: string) => unit

  /** Appends `node`, moving it if it's already a child. */
  let appendChild: (instance, node) => unit
  /** Inserts `node` before `before`, moving it if it's already a child. */
  let insertBefore: (instance, node, ~before: node) => unit
  let removeChild: (instance, node) => unit
  let appendChildToContainer: (container, node) => unit
  let insertInContainerBefore: (container, node, ~before: node) => unit
  let removeChildFromContainer: (container, node) => unit

  let prepareForCommit: container => unit
  let resetAfterCommit: container => unit
}

/** What a `Suspense` boundary's markers in server-rendered content say. */
type suspenseState =
  /** Its content is in place. */
  | Complete
  /** Its fallback is showing; its content is still to come (`onSuspenseReady`). */
  | Pending
  /** Its content failed on the server: the client renders the boundary itself. */
  | Failed

/**
A host that can hydrate: render over content that's already there (the server's HTML), adopting
its nodes rather than creating new ones. `Reconciler.MakeHydratable` takes one of these.

The reconciler walks the existing content with a cursor, a `hydratable` (a node, or a boundary's
markers): each host element claims the cursor's node if it's an instance of the same tag, each text a
text node, each `Suspense` boundary its markers. The host decides what's skipped (in the DOM, the
comments that only keep texts apart) and where a boundary's content starts and ends. Nothing is
changed during rendering: what hydration removes or patches, it does at commit.
*/
module type Hydratable = {
  include S

  /** A node of the existing content, or a boundary's start marker: where the cursor can be. */
  type hydratable
  /** A `Suspense` boundary's markers, and what's between them. */
  type suspenseInstance

  let firstHydratableChildOfContainer: container => option<hydratable>
  let firstHydratableChild: instance => option<hydratable>
  /** The next hydratable node after `hydratable` in its parent, or `None` at the end (or a boundary's end marker). */
  let nextHydratableSibling: hydratable => option<hydratable>

  /** `hydratable` as an instance of `tag`, if it is one. */
  let asInstance: (hydratable, ~tag: string) => option<instance>
  let asTextInstance: hydratable => option<textInstance>
  let asSuspenseInstance: hydratable => option<suspenseInstance>

  /**
  Whether an element of `tag` keeps its content itself (a `textarea`, whose text is its value):
  hydration neither claims nor removes its children.
  */
  let keepsOwnContent: (~tag: string) => bool

  /**
  Attaches what the server couldn't write (handlers, the stored props) to a claimed instance. May
  warn, in development, about attributes that differ; it doesn't change them.
  */
  let hydrateInstance: (instance, ~tag: string, ~props: props) => unit
  /** Whether a claimed text node already has `text` (if not, it's patched at commit). */
  let textMatches: (textInstance, ~text: string) => bool

  let suspenseState: suspenseInstance => suspenseState
  /** The first hydratable node inside the boundary. */
  let firstHydratableInSuspense: suspenseInstance => option<hydratable>
  /** The first hydratable node after the boundary's end marker. */
  let nextHydratableAfterSuspense: suspenseInstance => option<hydratable>
  /** The boundary's start marker, as a node: what's inserted before, ahead of a dehydrated boundary. */
  let suspenseInstanceToNode: suspenseInstance => node
  /** Calls `retry` once a pending boundary's content has arrived (at once if it already has). */
  let onSuspenseReady: (suspenseInstance, unit => unit) => unit
  /** Removes the boundary's markers and everything between them (to render it on the client). */
  let clearSuspense: suspenseInstance => unit

  /** Removes a node hydration didn't claim. */
  let removeHydratable: hydratable => unit
  /** Removes everything in the container (to render the root on the client after all). */
  let clearContainer: container => unit
  /** For messages: what `hydratable` is (`<div id="a">`, the text "x"). */
  let describeHydratable: hydratable => string
}
