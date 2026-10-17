/***
Diffs a fiber's current children against the elements it rendered, producing the work-in-progress
children: reusing a fiber where the key and type match, creating one where they don't, and recording
what the commit phase must do (`Placement` for new and moved fibers, `deletions` on the parent).

This is React's algorithm. `~track=false` is for a parent being mounted: nothing below it is on
screen yet, so there is nothing to delete or move, and the parent's own placement inserts the whole
subtree at once.
*/

open Fiber

let tagOfKind = (kind: Element.kind): Fiber.tag =>
  switch kind {
  | Host => HostComponent
  | Component => FunctionComponent
  | Fragment => Fragment
  | Provider => ContextProvider
  | Memo => MemoComponent
  | ErrorBoundary => ErrorBoundaryComponent
  | Portal => HostPortal
  | Suspense => SuspenseComponent
  | Offscreen => OffscreenComponent
  }

let createFiberFromText = (text: string): Fiber.t =>
  Fiber.make(~tag=HostText, ~key=Nullable.null, ~pendingProps=Unsafe.toUnknown(text))

/** A fragment fiber's props are its children: an element. */
let createFiberFromFragment = (children: Element.t, key: Nullable.t<string>): Fiber.t =>
  Fiber.make(~tag=Fragment, ~key, ~pendingProps=Unsafe.toUnknown(children))

let createFiberFromNode = (node: Element.node): Fiber.t =>
  switch node.kind {
  | Fragment => createFiberFromFragment(Element.childrenOf(node.props), node.key)
  | kind =>
    let fiber = Fiber.make(~tag=tagOfKind(kind), ~key=node.key, ~pendingProps=node.props)
    fiber.elementType = node.elementType
    if kind == Portal {
      fiber.stateNode = node.elementType
    }
    fiber
  }

/** Whether `fiber` can be reused for `node` (whose key already matches). */
let sameType = (fiber: Fiber.t, node: Element.node): bool =>
  switch node.kind {
  | Fragment => fiber.tag == Fragment
  | kind => fiber.tag == tagOfKind(kind) && fiber.elementType === node.elementType
  }

let pendingPropsOf = (node: Element.node): unknown =>
  switch node.kind {
  | Fragment => Unsafe.toUnknown(Element.childrenOf(node.props))
  | Host | Component | Provider | Memo | ErrorBoundary | Portal | Suspense | Offscreen => node.props
  }

/** A work-in-progress copy of `fiber` with new props, as the only child so far. */
let useFiber = (fiber: Fiber.t, pendingProps: unknown): Fiber.t => {
  let clone = Fiber.createWorkInProgress(fiber, pendingProps)
  clone.index = 0
  clone.sibling = None
  clone
}

let adopt = (returnFiber: Fiber.t, fiber: Fiber.t): Fiber.t => {
  fiber.parent = Some(returnFiber)
  fiber
}

let deleteChild = (~track, returnFiber: Fiber.t, child: Fiber.t) =>
  if track {
    switch returnFiber.deletions {
    | Some(deletions) => deletions->Array.push(child)
    | None =>
      returnFiber.deletions = Some([child])
      addFlag(returnFiber, Flags.childDeletion)
    }
  }

let deleteRemainingChildren = (~track, returnFiber: Fiber.t, first: option<Fiber.t>) =>
  if track {
    let child = ref(first)
    while Option.isSome(child.contents) {
      let fiber = Option.getUnsafe(child.contents)
      deleteChild(~track, returnFiber, fiber)
      child := fiber.sibling
    }
  }

/**
Records `newFiber` at `newIndex`, and returns the new `lastPlacedIndex`: the highest old index among
the fibers kept in place so far. A reused fiber whose old index is below that has moved forward past
a kept one, so it's placed again; anything else stays where it is.
*/
let placeChild = (~track, newFiber: Fiber.t, lastPlacedIndex: int, newIndex: int): int => {
  newFiber.index = newIndex
  if !track {
    lastPlacedIndex
  } else {
    switch newFiber.alternate {
    | Some(current) =>
      if current.index < lastPlacedIndex {
        addFlag(newFiber, Flags.placement)
        lastPlacedIndex
      } else {
        current.index
      }
    | None =>
      addFlag(newFiber, Flags.placement)
      lastPlacedIndex
    }
  }
}

let placeSingleChild = (~track, newFiber: Fiber.t): Fiber.t => {
  if track && Option.isNone(newFiber.alternate) {
    addFlag(newFiber, Flags.placement)
  }
  newFiber
}

let updateTextNode = (returnFiber: Fiber.t, current: option<Fiber.t>, text: string): Fiber.t =>
  switch current {
  | Some(current) if current.tag == HostText =>
    adopt(returnFiber, useFiber(current, Unsafe.toUnknown(text)))
  | _ => adopt(returnFiber, createFiberFromText(text))
  }

let updateFragment = (
  returnFiber: Fiber.t,
  current: option<Fiber.t>,
  children: Element.t,
  key: Nullable.t<string>,
): Fiber.t =>
  switch current {
  | Some(current) if current.tag == Fragment =>
    adopt(returnFiber, useFiber(current, Unsafe.toUnknown(children)))
  | _ => adopt(returnFiber, createFiberFromFragment(children, key))
  }

let updateElement = (returnFiber: Fiber.t, current: option<Fiber.t>, node: Element.node): Fiber.t =>
  switch current {
  | Some(current) if sameType(current, node) =>
    adopt(returnFiber, useFiber(current, pendingPropsOf(node)))
  | _ => adopt(returnFiber, createFiberFromNode(node))
  }

/** A new fiber for `child`, or `None` if it renders nothing. */
let createChild = (returnFiber: Fiber.t, child: Element.t): option<Fiber.t> =>
  switch Element.classify(child) {
  | Text(text) => Some(adopt(returnFiber, createFiberFromText(text)))
  | Node(node) => Some(adopt(returnFiber, createFiberFromNode(node)))
  | List(_) => Some(adopt(returnFiber, createFiberFromFragment(child, Nullable.null)))
  | Empty => None
  }

/**
The fiber for `child` in `oldFiber`'s slot, or `None` if the keys don't match (or `child` renders
nothing), which ends the in-order pass of `reconcileChildrenArray`.
*/
let updateSlot = (returnFiber: Fiber.t, oldFiber: option<Fiber.t>, child: Element.t): option<
  Fiber.t,
> => {
  let key = switch oldFiber {
  | Some(oldFiber) => oldFiber.key
  | None => Nullable.null
  }
  let unkeyed = Nullable.isNullable(key)
  switch Element.classify(child) {
  | Text(text) => unkeyed ? Some(updateTextNode(returnFiber, oldFiber, text)) : None
  | Node(node) => node.key === key ? Some(updateElement(returnFiber, oldFiber, node)) : None
  | List(_) => unkeyed ? Some(updateFragment(returnFiber, oldFiber, child, Nullable.null)) : None
  | Empty => None
  }
}

/** The key a fiber is found under in `mapRemainingChildren`: its key, or else its index. */
let mapKey = (key: Nullable.t<string>, index: int): unknown =>
  switch Nullable.toOption(key) {
  | Some(key) => Unsafe.toUnknown(key)
  | None => Unsafe.toUnknown(index)
  }

let mapRemainingChildren = (first: Fiber.t): Map.t<unknown, Fiber.t> => {
  let existing = Map.make()
  let child = ref(Some(first))
  while Option.isSome(child.contents) {
    let fiber = Option.getUnsafe(child.contents)
    existing->Map.set(mapKey(fiber.key, fiber.index), fiber)
    child := fiber.sibling
  }
  existing
}

let updateFromMap = (
  existing: Map.t<unknown, Fiber.t>,
  returnFiber: Fiber.t,
  newIndex: int,
  child: Element.t,
): option<Fiber.t> => {
  let byIndex = () => existing->Map.get(Unsafe.toUnknown(newIndex))
  switch Element.classify(child) {
  | Text(text) => Some(updateTextNode(returnFiber, byIndex(), text))
  | Node(node) =>
    Some(updateElement(returnFiber, existing->Map.get(mapKey(node.key, newIndex)), node))
  | List(_) => Some(updateFragment(returnFiber, byIndex(), child, Nullable.null))
  | Empty => None
  }
}

let reconcileChildrenArray = (
  ~track,
  returnFiber: Fiber.t,
  currentFirstChild: option<Fiber.t>,
  newChildren: array<Element.t>,
): option<Fiber.t> => {
  if ResCommon.Env.isDev {
    KeyWarnings.check(returnFiber, newChildren)
  }
  let length = Array.length(newChildren)
  let first = ref(None)
  let previous = ref(None)
  let link = (fiber: Fiber.t) => {
    switch previous.contents {
    | Some(previous) => previous.sibling = Some(fiber)
    | None => first := Some(fiber)
    }
    previous := Some(fiber)
  }
  let lastPlacedIndex = ref(0)
  let newIndex = ref(0)
  let oldFiber = ref(currentFirstChild)

  // First pass: walk the old and new children in step while their keys match.
  let matching = ref(true)
  while matching.contents && Option.isSome(oldFiber.contents) && newIndex.contents < length {
    let old = Option.getUnsafe(oldFiber.contents)
    // An old fiber whose index is ahead of `newIndex` left a gap (a child that rendered nothing):
    // nothing old sits in this slot.
    let (slot, nextOld) =
      old.index > newIndex.contents ? (None, Some(old)) : (Some(old), old.sibling)
    switch updateSlot(returnFiber, slot, newChildren->Array.getUnsafe(newIndex.contents)) {
    | None => matching := false
    | Some(newFiber) =>
      switch slot {
      | Some(slot) if track && Option.isNone(newFiber.alternate) =>
        deleteChild(~track, returnFiber, slot)
      | _ => ()
      }
      lastPlacedIndex := placeChild(~track, newFiber, lastPlacedIndex.contents, newIndex.contents)
      link(newFiber)
      oldFiber := nextOld
      newIndex := newIndex.contents + 1
    }
  }

  if newIndex.contents == length {
    deleteRemainingChildren(~track, returnFiber, oldFiber.contents)
  } else {
    switch oldFiber.contents {
    | None =>
      // Only insertions are left.
      for index in newIndex.contents to length - 1 {
        switch createChild(returnFiber, newChildren->Array.getUnsafe(index)) {
        | Some(newFiber) =>
          lastPlacedIndex := placeChild(~track, newFiber, lastPlacedIndex.contents, index)
          link(newFiber)
        | None => ()
        }
      }
    | Some(remaining) =>
      // Moves: find the rest of the new children among the old ones by key.
      let existing = mapRemainingChildren(remaining)
      for index in newIndex.contents to length - 1 {
        switch updateFromMap(existing, returnFiber, index, newChildren->Array.getUnsafe(index)) {
        | Some(newFiber) =>
          switch newFiber.alternate {
          | Some(reused) if track => existing->Map.delete(mapKey(reused.key, reused.index))->ignore
          | _ => ()
          }
          lastPlacedIndex := placeChild(~track, newFiber, lastPlacedIndex.contents, index)
          link(newFiber)
        | None => ()
        }
      }
      existing->Map.forEach(child => deleteChild(~track, returnFiber, child))
    }
  }
  first.contents
}

let reconcileSingleElement = (
  ~track,
  returnFiber: Fiber.t,
  currentFirstChild: option<Fiber.t>,
  node: Element.node,
): Fiber.t => {
  let rec findReusable = (child: option<Fiber.t>): option<Fiber.t> =>
    switch child {
    | None => None
    | Some(child) if child.key === node.key =>
      if sameType(child, node) {
        deleteRemainingChildren(~track, returnFiber, child.sibling)
        Some(adopt(returnFiber, useFiber(child, pendingPropsOf(node))))
      } else {
        deleteRemainingChildren(~track, returnFiber, Some(child))
        None
      }
    | Some(child) =>
      deleteChild(~track, returnFiber, child)
      findReusable(child.sibling)
    }
  switch findReusable(currentFirstChild) {
  | Some(fiber) => fiber
  | None => adopt(returnFiber, createFiberFromNode(node))
  }
}

let reconcileSingleTextNode = (
  ~track,
  returnFiber: Fiber.t,
  currentFirstChild: option<Fiber.t>,
  text: string,
): Fiber.t =>
  switch currentFirstChild {
  | Some(first) if first.tag == HostText =>
    deleteRemainingChildren(~track, returnFiber, first.sibling)
    adopt(returnFiber, useFiber(first, Unsafe.toUnknown(text)))
  | _ =>
    deleteRemainingChildren(~track, returnFiber, currentFirstChild)
    adopt(returnFiber, createFiberFromText(text))
  }

/**
The new first child of `returnFiber`, from its current first child and the element it rendered. An
unkeyed `<>...</>` at the top is the same as its contents, so switching between the two keeps state.
*/
let reconcileChildFibers = (
  ~track,
  returnFiber: Fiber.t,
  currentFirstChild: option<Fiber.t>,
  newChild: Element.t,
): option<Fiber.t> => {
  let newChild = switch Element.classify(newChild) {
  | Node({kind: Fragment, key, props}) if Nullable.isNullable(key) => Element.childrenOf(props)
  | _ => newChild
  }
  switch Element.classify(newChild) {
  | Node(node) =>
    Some(
      placeSingleChild(
        ~track,
        reconcileSingleElement(~track, returnFiber, currentFirstChild, node),
      ),
    )
  | Text(text) =>
    Some(
      placeSingleChild(
        ~track,
        reconcileSingleTextNode(~track, returnFiber, currentFirstChild, text),
      ),
    )
  | List(children) => reconcileChildrenArray(~track, returnFiber, currentFirstChild, children)
  | Empty =>
    deleteRemainingChildren(~track, returnFiber, currentFirstChild)
    None
  }
}

/** Sets `workInProgress.child` from the element it rendered. */
let reconcileChildren = (
  current: option<Fiber.t>,
  workInProgress: Fiber.t,
  nextChildren: Element.t,
) =>
  workInProgress.child = switch current {
  | None => reconcileChildFibers(~track=false, workInProgress, None, nextChildren)
  | Some(current) => reconcileChildFibers(~track=true, workInProgress, current.child, nextChildren)
  }

/**
Like `reconcileChildren`, but tracks placements even when the portal is new: its children go in its
own container, so the host parent's `appendAllChildren` skips them and each is placed on its own.
*/
let reconcilePortalChildren = (
  current: option<Fiber.t>,
  workInProgress: Fiber.t,
  nextChildren: Element.t,
) =>
  workInProgress.child = reconcileChildFibers(
    ~track=true,
    workInProgress,
    current->Option.flatMap(current => current.child),
    nextChildren,
  )
