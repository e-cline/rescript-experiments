/***
A host for the benchmarks: in-memory nodes that cost about what DOM nodes cost the reconciler to
drive, and nothing more. Children are a doubly linked list, so appending, inserting before a
sibling and removing are all constant time (as in the DOM, and unlike an array's `indexOf` and
`splice`, which would make moving rows quadratic and measure the host instead of the reconciler).
Props are the test renderer's (`Weft.TestJsx`), so the benchmarks are written in that JSX.
*/

type rec node = {
  tag: string,
  mutable props: Weft.TestJsx.Elements.props,
  mutable text: string,
  mutable parent: option<node>,
  mutable previous: option<node>,
  mutable next: option<node>,
  mutable first: option<node>,
  mutable last: option<node>,
}

let makeNode = (~tag, ~props, ~text) => {
  tag,
  props,
  text,
  parent: None,
  previous: None,
  next: None,
  first: None,
  last: None,
}

let detach = (child: node) => {
  switch child.parent {
  | Some(parent) =>
    switch child.previous {
    | Some(previous) => previous.next = child.next
    | None => parent.first = child.next
    }
    switch child.next {
    | Some(next) => next.previous = child.previous
    | None => parent.last = child.previous
    }
  | None => ()
  }
  child.parent = None
  child.previous = None
  child.next = None
}

let append = (parent: node, child: node) => {
  detach(child)
  child.parent = Some(parent)
  child.previous = parent.last
  switch parent.last {
  | Some(last) => last.next = Some(child)
  | None => parent.first = Some(child)
  }
  parent.last = Some(child)
}

let insertBefore = (parent: node, child: node, before: node) => {
  detach(child)
  child.parent = Some(parent)
  child.next = Some(before)
  child.previous = before.previous
  switch before.previous {
  | Some(previous) => previous.next = Some(child)
  | None => parent.first = Some(child)
  }
  before.previous = Some(child)
}

/** The number of nodes under `node`, to check a benchmark did what it should. */
let rec count = (node: node) => {
  let total = ref(0)
  let child = ref(node.first)
  while Option.isSome(child.contents) {
    let c = Option.getUnsafe(child.contents)
    total := total.contents + 1 + count(c)
    child := c.next
  }
  total.contents
}

type container = node
type instance = node
type textInstance = node
type props = Weft.TestJsx.Elements.props
type updatePayload = unit
type publicInstance = Weft.TestJsx.node

external toPublic: node => Weft.TestJsx.node = "%identity"

let instanceToNode = (node: node) => node
let textToNode = (node: node) => node
let getPublicInstance = toPublic

let createInstance = (~tag, ~props, ~container as _) => makeNode(~tag, ~props, ~text="")
let createTextInstance = (text, ~container as _) => makeNode(~tag="#text", ~props={}, ~text)
let appendInitialChild = append
let finalizeInitialChildren = (_: node, ~tag as _, ~props as _) => ()

let prepareUpdate = (_: node, ~tag as _, ~oldProps: props, ~newProps: props) =>
  oldProps.id === newProps.id &&
  oldProps.className === newProps.className &&
  oldProps.title === newProps.title
    ? None
    : Some()

let commitUpdate = (node: node, (), ~tag as _, ~oldProps as _, ~newProps) => node.props = newProps
let commitTextUpdate = (node: node, ~oldText as _, ~newText) => node.text = newText
let hideInstance = (_: node) => ()
let unhideInstance = (_: node, ~props as _) => ()
let hideTextInstance = (_: node) => ()
let unhideTextInstance = (_: node, ~text as _) => ()

let appendChild = append
let insertBefore = (parent, child, ~before) => insertBefore(parent, child, before)
let removeChild = (_: node, child: node) => detach(child)
let appendChildToContainer = append
let insertInContainerBefore = insertBefore
let removeChildFromContainer = removeChild

let prepareForCommit = (_: node) => ()
let resetAfterCommit = (_: node) => ()
