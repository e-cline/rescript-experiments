/***
The fiber: one node of the tree the reconciler keeps for each mounted element.

There are two trees. `current` is what's on screen; a render builds the work-in-progress tree from
it, and committing makes that the new `current`. Each fiber's `alternate` is its counterpart in the
other tree, and `createWorkInProgress` reuses it, so steady-state renders allocate no fibers.

The record is host-independent (hooks and the render phase don't know the renderer), so
`stateNode`, props and state are `unknown`; the code that stores each value is the code that reads
it back.
*/

type tag =
  | HostRoot
  | HostComponent
  | HostText
  | FunctionComponent
  | Fragment
  | ContextProvider
  | MemoComponent

/** A context a function component read while rendering, and the value it read. */
type dependency = {context: unknown, memoizedValue: unknown}

type rec t = {
  mutable tag: tag,
  key: Nullable.t<string>,
  /** Host: the tag name. Function component: its `make`. */
  mutable elementType: unknown,
  mutable pendingProps: unknown,
  /** The props of the last finished render. Host text: the text. Fragment: the children. */
  mutable memoizedProps: unknown,
  /** Host: the instance or text instance. Root: the `FiberRoot.t`. */
  mutable stateNode: unknown,
  mutable parent: option<t>,
  mutable child: option<t>,
  mutable sibling: option<t>,
  /** The position among its siblings when last reconciled. */
  mutable index: int,
  mutable alternate: option<t>,
  mutable flags: int,
  /** The union of every descendant's `flags`: the commit phase skips subtrees where it's 0. */
  mutable subtreeFlags: int,
  /** Children to remove at commit. */
  mutable deletions: option<array<t>>,
  /** Function component: its first hook. Root: the rendered element. */
  mutable memoizedState: unknown,
  /** Host component: the update payload for commit. Function component: its effects. */
  mutable updateQueue: unknown,
  /** Function component: the contexts it read in its last render. */
  mutable dependencies: option<array<dependency>>,
  mutable lanes: Lanes.t,
  mutable childLanes: Lanes.t,
}

module Flags = {
  let none = 0
  let placement = 2
  let update = 4
  let childDeletion = 16
  /** A function component has a `useEffect` to run. */
  let passive = 32
  /** A function component has a `useLayoutEffect` to run. */
  let layout = 64
  /** A host component's `ref` prop needs attaching (and the old one detaching). */
  let ref = 128

  let union = flags => flags->Array.reduce(none, Int.bitwiseOr)
  let mutationMask = union([placement, update, childDeletion, layout, ref])
  let layoutMask = union([layout, ref])
  let passiveMask = union([passive, childDeletion])
}

/** A fiber that renders a function with hooks. */
let isFunctionLike = (fiber: t) => fiber.tag == FunctionComponent || fiber.tag == MemoComponent

let hasFlag = (flags: int, flag: int): bool => Int.bitwiseAnd(flags, flag) != 0
let addFlag = (fiber: t, flag: int) => fiber.flags = Int.bitwiseOr(fiber.flags, flag)
let removeFlag = (fiber: t, flag: int) =>
  fiber.flags = Int.bitwiseAnd(fiber.flags, Int.bitwiseNot(flag))

let make = (~tag: tag, ~key: Nullable.t<string>, ~pendingProps: unknown): t => {
  tag,
  key,
  elementType: Unsafe.nothing,
  pendingProps,
  memoizedProps: Unsafe.nothing,
  stateNode: Unsafe.nothing,
  parent: None,
  child: None,
  sibling: None,
  index: 0,
  alternate: None,
  flags: Flags.none,
  subtreeFlags: Flags.none,
  deletions: None,
  memoizedState: Unsafe.nothing,
  updateQueue: Unsafe.nothing,
  dependencies: None,
  lanes: Lanes.none,
  childLanes: Lanes.none,
}

/**
The work-in-progress counterpart of `current`, with `pendingProps`: its `alternate`, reset, or a new
fiber the first time. Everything but the effect bookkeeping is copied from `current`, so a fiber that
bails out is identical to it.
*/
let createWorkInProgress = (current: t, pendingProps: unknown): t => {
  let workInProgress = switch current.alternate {
  | Some(workInProgress) =>
    workInProgress.pendingProps = pendingProps
    workInProgress.elementType = current.elementType
    workInProgress.flags = Flags.none
    workInProgress.subtreeFlags = Flags.none
    workInProgress.deletions = None
    workInProgress
  | None =>
    let workInProgress = make(~tag=current.tag, ~key=current.key, ~pendingProps)
    workInProgress.elementType = current.elementType
    workInProgress.stateNode = current.stateNode
    workInProgress.alternate = Some(current)
    current.alternate = Some(workInProgress)
    workInProgress
  }
  workInProgress.lanes = current.lanes
  workInProgress.childLanes = current.childLanes
  workInProgress.child = current.child
  workInProgress.memoizedProps = current.memoizedProps
  workInProgress.memoizedState = current.memoizedState
  workInProgress.updateQueue = current.updateQueue
  workInProgress.dependencies = current.dependencies
  workInProgress.sibling = current.sibling
  workInProgress.index = current.index
  workInProgress
}
