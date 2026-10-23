let textTag = "#text"
/** A comment: a `Suspense` boundary's marker, or what keeps two texts apart, in hydrated content. */
let commentTag = "#comment"

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
type hydratableNode = node

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

  // Hydrating: rendering over nodes parsed from markup (`hydrate`).

  /** A node among its siblings (a parent's children, or the container's). */
  type hydratable = {siblings: array<hydratableNode>, node: hydratableNode}
  /** A boundary's start marker, among its siblings. */
  type suspenseInstance = hydratable

  let isStartMarker = (node: node) =>
    node.tag == commentTag && (node.text == "$" || node.text == "$?" || node.text == "$!")
  let isEndMarker = (node: node) => node.tag == commentTag && node.text == "/$"

  /** The first hydratable node from `index` on: `None` at the end, or at a boundary's end marker. */
  let rec scan = (siblings: array<node>, index) =>
    switch siblings->Array.get(index) {
    | None => None
    | Some(node) if isEndMarker(node) => None
    // A comment that only keeps two texts apart.
    | Some(node) if node.tag == commentTag && !isStartMarker(node) => scan(siblings, index + 1)
    | Some(node) => Some({siblings, node})
    }

  let firstHydratableChildOfContainer = (container: container) => scan(container.rootChildren, 0)
  let firstHydratableChild = (instance: instance) => scan(instance.children, 0)
  let nextHydratableSibling = (hydratable: hydratable) =>
    scan(hydratable.siblings, hydratable.siblings->Array.indexOf(hydratable.node) + 1)

  let asInstance = (hydratable: hydratable, ~tag) =>
    hydratable.node.tag == tag ? Some(hydratable.node) : None
  let asTextInstance = (hydratable: hydratable) =>
    hydratable.node.tag == textTag ? Some(hydratable.node) : None
  let asSuspenseInstance = (hydratable: hydratable) =>
    isStartMarker(hydratable.node) ? Some(hydratable) : None

  let keepsOwnContent = (~tag) => tag == "textarea"

  let describeNode = (node: node) =>
    if node.tag == textTag {
      `the text "${node.text}"`
    } else if node.tag == commentTag {
      "a <Suspense> boundary's markers"
    } else {
      `<${describe(node)}>`
    }

  let describeHydratable = (hydratable: hydratable) => describeNode(hydratable.node)

  let shown = props => visibleProps(props)->Array.map(((name, value)) => (name, stringify(value)))

  let hydrateInstance = (instance: instance, ~tag as _, ~props) => {
    if Common.Env.isDev && shown(props) != shown(instance.props) {
      Console.error(
        `TestRenderer: the server's ${describeNode(instance)} has other props than the client's`,
      )
    }
    instance.props = props
    record(instance.owner, `hydrate ${describe(instance)}`)
  }

  let textMatches = (instance: textInstance, ~text) => instance.text == text

  let suspenseState = (instance: suspenseInstance): HostConfig.suspenseState =>
    switch instance.node.text {
    | "$" => Complete
    | "$?" => Pending
    | _ => Failed
    }

  /** Where the boundary's end marker is, among its siblings. */
  let endOf = (instance: suspenseInstance) => {
    let index = ref(instance.siblings->Array.indexOf(instance.node) + 1)
    let depth = ref(0)
    let found = ref(None)
    while Option.isNone(found.contents) && index.contents < Array.length(instance.siblings) {
      let node = instance.siblings->Array.getUnsafe(index.contents)
      if isStartMarker(node) {
        depth := depth.contents + 1
      } else if isEndMarker(node) {
        if depth.contents == 0 {
          found := Some(index.contents)
        } else {
          depth := depth.contents - 1
        }
      }
      index := index.contents + 1
    }
    switch found.contents {
    | Some(index) => index
    | None => JsError.throwWithMessage("TestRenderer: a boundary's start marker has no end marker")
    }
  }

  let firstHydratableInSuspense = (instance: suspenseInstance) =>
    scan(instance.siblings, instance.siblings->Array.indexOf(instance.node) + 1)
  let nextHydratableAfterSuspense = (instance: suspenseInstance) =>
    scan(instance.siblings, endOf(instance) + 1)
  let suspenseInstanceToNode = (instance: suspenseInstance) => instance.node

  /** The retries waiting on pending boundaries' markers. */
  let retries: Map.t<node, unit => unit> = Map.make()

  let onSuspenseReady = (instance: suspenseInstance, retry) =>
    instance.node.text == "$?" ? retries->Map.set(instance.node, retry) : retry()

  let clearSuspense = (instance: suspenseInstance) => {
    let start = instance.siblings->Array.indexOf(instance.node)
    let removed =
      instance.siblings->Array.splice(~start, ~remove=endOf(instance) - start + 1, ~insert=[])
    ignore(removed)
    record(instance.node.owner, "clear a boundary's server content")
  }

  let removeHydratable = (hydratable: hydratable) => {
    removeFrom(hydratable.siblings, hydratable.node)
    record(hydratable.node.owner, `remove ${describe(hydratable.node)}`)
  }

  let clearContainer = (container: container) => {
    container.rootChildren->Array.splice(
      ~start=0,
      ~remove=Array.length(container.rootChildren),
      ~insert=[],
    )
    record(container.log, `clear ${container.name}`)
  }
}

module Renderer = Reconciler.MakeHydratableWithScheduler(Host, TestScheduler)

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
  if node.hidden || node.tag == commentTag {
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

// Hydrating

/** An opening tag's `name="value"` attributes. */
let attributesOf: string => array<(string, string)> = %raw(`opening =>
  [...opening.matchAll(/ ([a-zA-Z0-9_-]+)="([^"]*)"/g)].map(([, name, value]) => [name, value])`)

/** Markup in `toString`'s format (with `<!--...-->` comments for markers), parsed into nodes. */
let parseMarkup = (markup: string, ~log: log): array<node> => {
  let at = ref(0)
  let length = String.length(markup)
  let make = (~tag, ~props, ~text) => {
    let uid = log.nextUid
    log.nextUid = uid + 1
    {uid, tag, props, text, children: [], hidden: false, owner: log}
  }
  let rest = () => markup->String.slice(~start=at.contents)
  let rec nodes = (~closing: option<string>) => {
    let found = []
    let finished = ref(false)
    while !finished.contents && at.contents < length {
      if rest()->String.startsWith("<!--") {
        let close = markup->String.indexOfFrom("-->", at.contents)
        found->Array.push(
          make(
            ~tag=commentTag,
            ~props={},
            ~text=markup->String.slice(~start=at.contents + 4, ~end=close),
          ),
        )
        at := close + 3
      } else if rest()->String.startsWith("</") {
        let close = markup->String.indexOfFrom(">", at.contents)
        let tag = markup->String.slice(~start=at.contents + 2, ~end=close)
        if Some(tag) != closing {
          JsError.throwWithMessage(`TestRenderer: </${tag}> closes nothing in the markup`)
        }
        at := close + 1
        finished := true
      } else if rest()->String.startsWith("<") {
        let close = markup->String.indexOfFrom(">", at.contents)
        let opening = markup->String.slice(~start=at.contents + 1, ~end=close)
        at := close + 1
        let tag = opening->String.split(" ")->Array.getUnsafe(0)
        let props = Dict.fromArray(attributesOf(opening))
        let node = make(~tag, ~props=Unsafe.fromUnknown(Unsafe.toUnknown(props)), ~text="")
        node.children = nodes(~closing=Some(tag))
        found->Array.push(node)
      } else {
        let next = markup->String.indexOfFrom("<", at.contents)
        let stop = next == -1 ? length : next
        found->Array.push(
          make(~tag=textTag, ~props={}, ~text=markup->String.slice(~start=at.contents, ~end=stop)),
        )
        at := stop
      }
    }
    found
  }
  nodes(~closing=None)
}

let hydrate = (markup, element) => {
  let log = {ops: [], nextUid: 0}
  let container = {name: "root", rootChildren: parseMarkup(markup, ~log), log}
  let root = ref(None)
  act(() => root := Some(Renderer.hydrateRoot(container, element)))
  {container, root: Option.getUnsafe(root.contents), targets: []}
}

let rec markupOf = (node: node) =>
  if node.tag == textTag {
    node.text
  } else if node.tag == commentTag {
    `<!--${node.text}-->`
  } else {
    let attributes =
      visibleProps(node.props)
      ->Array.map(((name, value)) => ` ${name}="${stringify(value)}"`)
      ->Array.join("")
    `<${node.tag}${attributes}>${node.children->Array.map(markupOf)->Array.join("")}</${node.tag}>`
  }

let toMarkup = renderer => renderer.container.rootChildren->Array.map(markupOf)->Array.join("")

/** The first pending boundary's start marker (`<!--$?-->`), among its siblings. */
let firstPending = (renderer): option<(array<node>, int)> => {
  let rec find = (nodes: array<node>) =>
    nodes->Array.reduceWithIndex(None, (found, node, index) =>
      switch found {
      | Some(_) => found
      | None =>
        node.tag == commentTag && node.text == "$?" ? Some((nodes, index)) : find(node.children)
      }
    )
  find(renderer.container.rootChildren)
}

let pendingMarker = renderer =>
  switch firstPending(renderer) {
  | Some(found) => found
  | None => JsError.throwWithMessage("TestRenderer: no boundary is pending")
  }

let resolveBoundary = (renderer, markup) => {
  let (siblings, start) = pendingMarker(renderer)
  let marker = siblings->Array.getUnsafe(start)
  let end_ = Host.endOf({siblings, node: marker})
  // The server's segment arriving: the fallback goes, and the content takes its place.
  siblings->Array.splice(
    ~start=start + 1,
    ~remove=end_ - start - 1,
    ~insert=parseMarkup(markup, ~log=renderer.container.log),
  )
  marker.text = "$"
  act(() => Host.retries->Map.get(marker)->Option.forEach(retry => retry()))
}

let failBoundary = renderer => {
  let (siblings, start) = pendingMarker(renderer)
  let marker = siblings->Array.getUnsafe(start)
  marker.text = "$!"
  act(() => Host.retries->Map.get(marker)->Option.forEach(retry => retry()))
}
