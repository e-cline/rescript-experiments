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
