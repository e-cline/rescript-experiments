let textTag = "#text"

type rec node = {
  uid: int,
  tag: string,
  mutable props: TestJsx.Elements.props,
  mutable text: string,
  mutable children: array<node>,
  /** Hidden behind a `Suspense` fallback: left out of `toString`. */
  mutable hidden: bool,
  owner: log,
}
/** A root's container, or a portal target: named in the log. */
and container = {
  name: string,
  mutable rootChildren: array<node>,
  log: log,
}
/** Shared by a renderer's root and its portal targets. */
and log = {
  mutable ops: array<string>,
  mutable nextUid: int,
}

external propsToDict: TestJsx.Elements.props => dict<unknown> = "%identity"
@val external stringify: unknown => string = "String"

/** The props `toString` shows and `update` logs: not `children`, `ref` or handlers. */
let visibleProps = (props: TestJsx.Elements.props): array<(string, unknown)> =>
  propsToDict(props)
  ->Dict.toArray
  ->Array.filter(((name, value)) =>
    name != "children" && name != "ref" && Type.typeof(value) != #function
  )
  ->Array.toSorted(((a, _), (b, _)) => String.compare(a, b))

let describe = (node: node) =>
  if node.tag == textTag {
    `"${node.text}"`
  } else {
    switch node.props.id {
    | Some(id) => `${node.tag}#${id}`
    | None => node.tag
    }
  }

let removeFrom = (children: array<node>, child: node) =>
  switch children->Array.indexOf(child) {
  | -1 => ()
  | index => children->Array.splice(~start=index, ~remove=1, ~insert=[])
  }

let insertInto = (children: array<node>, child: node, ~before: node) => {
  removeFrom(children, child)
  switch children->Array.indexOf(before) {
  | -1 => JsError.throwWithMessage(`TestRenderer: ${describe(before)} is not a child`)
  | index => children->Array.splice(~start=index, ~remove=0, ~insert=[child])
  }
}

type hostNode = node

external toPublic: node => TestJsx.node = "%identity"
external fromPublic: TestJsx.node => node = "%identity"

module Host = {
  type container = container
  type instance = hostNode
  type textInstance = hostNode
  type node = hostNode
  type props = TestJsx.Elements.props
  /** The names of the visible props that changed. */
  type updatePayload = array<string>
  type publicInstance = TestJsx.node

  let instanceToNode = (instance: instance): node => instance
  let textToNode = (instance: instance): node => instance
  let getPublicInstance = toPublic

  let record = (log: log, op: string) => log.ops->Array.push(op)

  let make = (container: container, ~tag, ~props, ~text) => {
    let uid = container.log.nextUid
    container.log.nextUid = uid + 1
    {uid, tag, props, text, children: [], hidden: false, owner: container.log}
  }

  let createInstance = (~tag, ~props, ~container) => {
    let instance = make(container, ~tag, ~props, ~text="")
    record(container.log, `create ${describe(instance)}`)
    instance
  }

  let createTextInstance = (text, ~container) => {
    let instance = make(container, ~tag=textTag, ~props={}, ~text)
    record(container.log, `create ${describe(instance)}`)
    instance
  }

  let appendInitialChild = (parent: instance, child: node) => parent.children->Array.push(child)

  let finalizeInitialChildren = (_: instance, ~tag as _, ~props as _) => ()

  let prepareUpdate = (_: instance, ~tag as _, ~oldProps, ~newProps) => {
    let oldVisible = Dict.fromArray(visibleProps(oldProps))
    let newVisible = Dict.fromArray(visibleProps(newProps))
    let names = Set.fromArray(
      Array.concat(Dict.keysToArray(oldVisible), Dict.keysToArray(newVisible)),
    )
    let changed =
      names
      ->Set.values
      ->Iterator.toArray
      ->Array.filter(name => !Object.is(oldVisible->Dict.get(name), newVisible->Dict.get(name)))
      ->Array.toSorted(String.compare)
    // Always an update, so handlers that changed reach the instance too.
    Some(changed)
  }

  let commitUpdate = (instance: instance, changed, ~tag as _, ~oldProps as _, ~newProps) => {
    instance.props = newProps
    if Array.length(changed) > 0 {
      record(instance.owner, `update ${describe(instance)} {${changed->Array.join(", ")}}`)
    }
  }

  let hide = (instance: instance) =>
    if !instance.hidden {
      instance.hidden = true
      record(instance.owner, `hide ${describe(instance)}`)
    }

  // Logged only for a node that was hidden: one shown for the first time isn't "unhidden".
  let unhide = (instance: instance) =>
    if instance.hidden {
      instance.hidden = false
      record(instance.owner, `unhide ${describe(instance)}`)
    }

  let hideInstance = hide
  let unhideInstance = (instance: instance, ~props) => {
    instance.props = props
    unhide(instance)
  }
  let hideTextInstance = hide
  let unhideTextInstance = (instance: instance, ~text) => {
    instance.text = text
    unhide(instance)
  }

  let commitTextUpdate = (instance: instance, ~oldText, ~newText) => {
    instance.text = newText
    record(instance.owner, `text "${oldText}" -> "${newText}"`)
  }

  let appendChild = (parent: instance, child: node) => {
    removeFrom(parent.children, child)
    parent.children->Array.push(child)
    record(parent.owner, `append ${describe(child)} to ${describe(parent)}`)
  }

  let insertBefore = (parent: instance, child: node, ~before: node) => {
    insertInto(parent.children, child, ~before)
    record(parent.owner, `insert ${describe(child)} before ${describe(before)}`)
  }

  let removeChild = (parent: instance, child: node) => {
    removeFrom(parent.children, child)
    record(parent.owner, `remove ${describe(child)}`)
  }

  let appendChildToContainer = (container: container, child: node) => {
    removeFrom(container.rootChildren, child)
    container.rootChildren->Array.push(child)
    record(container.log, `append ${describe(child)} to ${container.name}`)
  }

  let insertInContainerBefore = (container: container, child: node, ~before: node) => {
    insertInto(container.rootChildren, child, ~before)
    record(container.log, `insert ${describe(child)} before ${describe(before)}`)
  }

  let removeChildFromContainer = (container: container, child: node) => {
    removeFrom(container.rootChildren, child)
    record(container.log, `remove ${describe(child)}`)
  }

  let prepareForCommit = (_: container) => ()
  let resetAfterCommit = (_: container) => ()
}

module Renderer = Reconciler.MakeWithScheduler(Host, TestScheduler)

type t = {container: container, root: Renderer.root, targets: array<container>}

let create = () => {
  let container = {name: "root", rootChildren: [], log: {ops: [], nextUid: 0}}
  {container, root: Renderer.createRoot(container), targets: []}
}

type target = container

let createTarget = (renderer, name) => {
  let target = {name, rootChildren: [], log: renderer.container.log}
  renderer.targets->Array.push(target)
  target
}

let portal = (target: target, children) => Portal.create(~container=target, children)

let maxActRounds = 100

let act = f => {
  f()
  Renderer.flushAllWork()
  let rounds = ref(0)
  while Renderer.flushPassiveEffects() {
    rounds := rounds.contents + 1
    if rounds.contents > maxActRounds {
      JsError.throwWithMessage("TestRenderer: effects keep scheduling updates")
    }
    Renderer.flushAllWork()
  }
}

let render = (renderer, element) => act(() => Renderer.render(renderer.root, element))

let scheduleRender = (renderer, element) => Renderer.render(renderer.root, element)

let flushSync = Renderer.flushSync

let unmount = renderer => act(() => Renderer.unmount(renderer.root))

let rec nodeToString = (node: node) =>
  if node.hidden {
    ""
  } else if node.tag == textTag {
    node.text
  } else {
    let attributes =
      visibleProps(node.props)
      ->Array.map(((name, value)) => ` ${name}="${stringify(value)}"`)
      ->Array.join("")
    let children = node.children->Array.map(nodeToString)->Array.join("")
    `<${node.tag}${attributes}>${children}</${node.tag}>`
  }

let containerToString = (container: container) =>
  container.rootChildren->Array.map(nodeToString)->Array.join("")

let toString = renderer => containerToString(renderer.container)

let targetToString = containerToString

let ops = renderer => renderer.container.log.ops->Array.copy

let clearOps = renderer => renderer.container.log.ops = []

let findById = (renderer, id) => {
  let rec find = (nodes: array<node>) =>
    nodes->Array.reduce(None, (found, node) =>
      switch found {
      | Some(_) => found
      | None => node.props.id == Some(id) ? Some(toPublic(node)) : find(node.children)
      }
    )
  [renderer.container]
  ->Array.concat(renderer.targets)
  ->Array.reduce(None, (found, container) =>
    switch found {
    | Some(_) => found
    | None => find(container.rootChildren)
    }
  )
}

let findExn = (renderer, id) =>
  switch findById(renderer, id) {
  | Some(node) => fromPublic(node)
  | None => JsError.throwWithMessage(`TestRenderer: no element with id "${id}"`)
  }

let click = (renderer, id) =>
  switch findExn(renderer, id).props.onClick {
  | Some(onClick) => act(onClick)
  | None => JsError.throwWithMessage(`TestRenderer: #${id} has no onClick`)
  }

let input = (renderer, id, value) =>
  switch findExn(renderer, id).props.onInput {
  | Some(onInput) => act(() => onInput(value))
  | None => JsError.throwWithMessage(`TestRenderer: #${id} has no onInput`)
  }

type instance = TestJsx.node

let uid = node => fromPublic(node).uid
let tag = node => fromPublic(node).tag
let props = node => fromPublic(node).props
let text = node => fromPublic(node).text
let children = node => fromPublic(node).children->Array.map(toPublic)
