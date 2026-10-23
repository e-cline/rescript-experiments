@@directive("'use weft server'")

module Element = WeftCore.Element
module ServerRender = WeftCore.ServerRender

// A few Web stream, encoding and abort bindings (every runtime this targets has them built in).

type stream
type controller
type source = {
  start?: controller => unit,
  cancel?: unknown => unit,
}
@new external makeStream: source => stream = "ReadableStream"
@send external enqueue: (controller, Uint8Array.t) => unit = "enqueue"
@send external closeStream: controller => unit = "close"
@send external errorStream: (controller, unknown) => unit = "error"

type encoder
@new external makeEncoder: unit => encoder = "TextEncoder"
@send external encode: (encoder, string) => Uint8Array.t = "encode"

type signal
@get external isAborted: signal => bool = "aborted"
type listenerOptions = {once: bool}
@send
external onAbort: (signal, @as("abort") _, unit => unit, listenerOptions) => unit =
  "addEventListener"

external toUnknown: 'a => unknown = "%identity"
external fromUnknown: unknown => 'a = "%identity"
@val external stringify: unknown => string = "String"

// Escaping

let escapeText = text =>
  text
  ->String.replaceAll("&", "&amp;")
  ->String.replaceAll("<", "&lt;")
  ->String.replaceAll(">", "&gt;")

let escapeAttribute = text =>
  escapeText(text)->String.replaceAll(`"`, "&quot;")->String.replaceAll("'", "&#39;")

let lineSeparator = String.fromCharCode(0x2028)
let paragraphSeparator = String.fromCharCode(0x2029)

/** `text` as a string literal in an inline script, with nothing in it that could end the script. */
let scriptString = text =>
  JSON.stringify(JSON.String(text))
  ->String.replaceAll("<", "\\u003c")
  ->String.replaceAll(lineSeparator, "\\u2028")
  ->String.replaceAll(paragraphSeparator, "\\u2029")

// The swap runtime: written once, before the first segment.

let runtime = `$weftSwap=function(n){var a=document.getElementById("wb:"+n),t=document.getElementById("ws:"+n);if(!a||!t)return;var m=a.previousSibling,p=a.parentNode,e=a.nextSibling,d=0;while(e){if(e.nodeType===8){if(e.data==="/$"){if(d===0)break;d--}else if(e.data[0]==="$")d++}var x=e.nextSibling;p.removeChild(e);e=x}p.insertBefore(t.content,e);p.removeChild(a);t.parentNode.removeChild(t);m.data="$";if(m.$weftRetry)m.$weftRetry()};$weftFail=function(n,g,s){var a=document.getElementById("wb:"+n);if(!a)return;var m=a.previousSibling;a.removeAttribute("id");if(g!=null)a.setAttribute("data-digest",g);if(s!=null)a.setAttribute("data-message",s);m.data="$!";if(m.$weftRetry)m.$weftRetry()};`

// Element rules

let voidElements = [
  "area",
  "base",
  "br",
  "col",
  "embed",
  "hr",
  "img",
  "input",
  "link",
  "meta",
  "source",
  "track",
  "wbr",
]

/** Elements whose content isn't HTML text, which Weft has no way to write. */
let rawTextElements = ["script", "style"]

/** Elements an open `<p>` can't hold: the parser closes the `<p>` before them. */
let blockElements = [
  "address",
  "article",
  "aside",
  "blockquote",
  "details",
  "dialog",
  "div",
  "dl",
  "fieldset",
  "figcaption",
  "figure",
  "footer",
  "form",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "header",
  "hgroup",
  "hr",
  "main",
  "menu",
  "nav",
  "ol",
  "p",
  "pre",
  "section",
  "table",
  "ul",
]

let tableSections = ["tbody", "thead", "tfoot"]

let tagPattern = /^[a-zA-Z][a-zA-Z0-9-]*$/
let attributePattern = /^[a-zA-Z_:][a-zA-Z0-9_:.-]*$/

// The walk

type context = {
  /** The providers above, outermost first: what components' `useContext` reads. */
  contexts: array<ServerRender.contextValue>,
  /** The host elements above, innermost first. */
  ancestors: list<string>,
  /** The `value` of the `select` above, if any, for its options' `selected`. */
  selectValue: option<string>,
  /** For messages: how the walk got here, innermost first. */
  path: list<string>,
}

/**
A pending boundary's content, rendered later in a segment of its own. Its id is given when the
attempt that left it pending is written out, so attempts thrown away don't use ids up.
*/
type spawn = {mutable id: int, children: Element.t, context: context}

/** What an attempt writes: markup, or a boundary's error, reported only if the attempt is kept. */
type piece =
  | Markup(string)
  | Failure(exn)
  /** A pending boundary's anchor, `<template id="wb:N">`, whose `N` is given when it's written. */
  | Anchor(spawn)

/** One synchronous try at rendering part of the tree, into `buffer`. */
type attempt = {
  buffer: array<piece>,
  /** Whether the last thing written was text (so more text needs a separator first). */
  mutable lastWasText: bool,
  /** What it found not ready: if any, the attempt is thrown away and tried again once they settle. */
  pending: array<promise<unknown>>,
  /** The boundaries it left pending, to start if the attempt is kept. */
  spawns: array<spawn>,
}

type request = {
  onError: exn => option<string>,
  /** `renderToString`: every boundary waited for, none left pending. */
  waitForAll: bool,
  mutable nextBoundary: int,
  mutable aborted: bool,
}

let newAttempt = () => {buffer: [], lastWasText: false, pending: [], spawns: []}

let writeMarkup = (attempt, markup) => {
  attempt.buffer->Array.push(Markup(markup))
  attempt.lastWasText = false
}

let writeText = (attempt, text) =>
  if text != "" {
    // Two texts in a row would parse as one text node: the client renders two.
    if attempt.lastWasText {
      attempt.buffer->Array.push(Markup("<!-- -->"))
    }
    attempt.buffer->Array.push(Markup(escapeText(text)))
    attempt.lastWasText = true
  }

let where = context =>
  switch context.path {
  | list{} => "the root"
  | path => path->List.reverse->List.toArray->Array.join("")
  }

let fail = (context, code, message) =>
  Errors.fail(code, Common.Env.isDev ? `WeftDom: ${message}, at ${where(context)}` : "")

/** The warnings given so far, so each is given once. */
let warned: Set.t<string> = Set.make()

let warn = message =>
  if !(warned->Set.has(message)) {
    warned->Set.add(message)
    Console.error(message)
  }

/** Warns (in development) about nesting the HTML parser would repair, so hydration wouldn't match. */
let checkNesting = (context, tag) => {
  let parent = switch context.ancestors {
  | list{parent, ..._} => Some(parent)
  | list{} => None
  }
  let inside = name => context.ancestors->List.has(name, (a, b) => a == b)
  let problem = if blockElements->Array.includes(tag) && inside("p") {
    Some(`<${tag}> can't be inside a <p>: the parser ends the <p> before it`)
  } else if tag == "a" && inside("a") {
    Some("an <a> can't be inside an <a>: the parser ends the outer one first")
  } else if tag == "form" && inside("form") {
    Some("a <form> can't be inside a <form>: the parser drops the inner one")
  } else if tag == "tr" && parent == Some("table") {
    Some("a <tr> straight in a <table> gets a <tbody> from the parser: write the <tbody>")
  } else if (tag == "td" || tag == "th") && parent != Some("tr") {
    Some(`a <${tag}> belongs in a <tr>`)
  } else if tableSections->Array.includes(tag) && parent != Some("table") {
    Some(`a <${tag}> belongs in a <table>`)
  } else {
    None
  }
  problem->Option.forEach(problem =>
    warn(
      `WeftDom: ${problem}, so the page's HTML wouldn't hydrate as rendered. At ${where(context)}.`,
    )
  )
}

@get external functionName: unknown => string = "name"

let componentName = (make: unknown) =>
  switch functionName(make) {
  | "" => "an anonymous component"
  | name => name->String.replaceAll("$", ".")
  }

/** The digest `onError` gives `error`, and (in development) its message. */
let report = (request, error: exn) => {
  let digest = try request.onError(error) catch {
  | _ => None
  }
  let message = Common.Env.isDev ? Some(WeftCore.ErrorBoundary.message(error)) : None
  (digest, message)
}

let errorAttributes = ((digest, message)) =>
  digest->Option.mapOr("", digest => ` data-digest="${escapeAttribute(digest)}"`) ++
    message->Option.mapOr("", message => ` data-message="${escapeAttribute(message)}"`)

type boundaryProps = {fallback: Element.t, children: Element.t}
external toBoundaryProps: unknown => boundaryProps = "%identity"
external toProps: unknown => dict<unknown> = "%identity"
external toComponent: unknown => unknown => Element.t = "%identity"

let optionalString = (value: option<unknown>) =>
  switch value {
  | Some(value) if !DomProps.isNothing(value) => Some(stringify(value))
  | _ => None
  }

/** The text of a list of children, if it's only text (an `option`'s value without a `value` prop). */
let rec textOf = (element: Element.t): option<string> =>
  switch Element.classify(element) {
  | Empty => Some("")
  | Text(text) => Some(text)
  | List(items) =>
    items->Array.reduce(Some(""), (text, item) =>
      switch (text, textOf(item)) {
      | (Some(text), Some(more)) => Some(text ++ more)
      | _ => None
      }
    )
  | Node(_) => None
  }

let styleAttribute = (value: unknown) =>
  if DomProps.isNothing(value) {
    ""
  } else {
    let style: dict<string> = fromUnknown(value)
    let declarations =
      style
      ->Dict.toArray
      ->Array.filter(((_, value)) => !DomProps.isNothing(toUnknown(value)))
      // As the browser serializes a style (`cssText`), so the attribute reads the same either way.
      ->Array.map(((name, value)) => `${DomProps.cssName(name)}: ${value};`)
    Array.length(declarations) == 0
      ? ""
      : ` style="${escapeAttribute(declarations->Array.join(" "))}"`
  }

/** The attributes for a host element's props (everything but its children). */
let attributes = (context, tag, props: dict<unknown>) => {
  let written = []
  props->Dict.forEachWithKey((value, name) =>
    switch name {
    | "children" | "ref" | "key" => ()
    | name if DomProps.isEventProp(name) => ()
    | "style" => written->Array.push(styleAttribute(value))
    // A textarea's value is its text, and a select's is its options' `selected`.
    | "value" if tag == "textarea" || tag == "select" => ()
    | name =>
      let attribute = DomProps.attributeName(name)
      if !RegExp.test(attributePattern, attribute) {
        fail(context, 2, `"${attribute}" isn't an attribute name`)
      }
      switch DomProps.attributeValue(value) {
      | Some(text) =>
        written->Array.push(
          text == "" ? ` ${attribute}=""` : ` ${attribute}="${escapeAttribute(text)}"`,
        )
      | None => ()
      }
    }
  )
  if tag == "option" {
    switch context.selectValue {
    | Some(selected) =>
      let value = switch optionalString(props->Dict.get("value")) {
      | Some(value) => Some(value)
      | None => textOf(Element.childrenOf(toUnknown(props)))
      }
      if value == Some(selected) && !(props->Dict.has("selected")) {
        written->Array.push(` selected=""`)
      }
    | None => ()
    }
  }
  written->Array.join("")
}

let rec renderElement = (request, attempt, context, element: Element.t) =>
  switch Element.classify(element) {
  | Empty => ()
  | Text(text) => writeText(attempt, text)
  | List(items) => items->Array.forEach(item => renderElement(request, attempt, context, item))
  | Node(node) => renderNode(request, attempt, context, node)
  }

and renderNode = (request, attempt, context, node: Element.node) =>
  switch node.kind {
  | Host => renderHost(request, attempt, context, node)
  | Component | Memo =>
    let make = node.elementType
    let context = {...context, path: list{`<${componentName(make)}>`, ...context.path}}
    switch ServerRender.renderComponent(
      toComponent(make),
      node.props,
      {contexts: context.contexts},
    ) {
    | output => renderElement(request, attempt, context, output)
    | exception error =>
      switch ServerRender.suspendedOn(error) {
      | Some(promise) => attempt.pending->Array.push(promise)
      | None => throw(error)
      }
    }
  | Fragment | ErrorBoundary =>
    // An error boundary doesn't catch on the server (its fallback would be the HTML, which the
    // client, rendering the children, would never match): the error goes to a `Suspense` above.
    renderElement(request, attempt, context, Element.childrenOf(node.props))
  | Provider =>
    let context = {
      ...context,
      contexts: [...context.contexts, ServerRender.providedContext(node)],
    }
    renderElement(request, attempt, context, Element.childrenOf(node.props))
  | Suspense => renderBoundary(request, attempt, context, node)
  | Lazy =>
    let promise = WeftCore.Lazy.promiseOf(node)
    switch ServerRender.run(() => WeftCore.Hooks.use(promise)) {
    | resolved => renderElement(request, attempt, context, resolved)
    | exception error =>
      switch ServerRender.suspendedOn(error) {
      | Some(promise) => attempt.pending->Array.push(promise)
      | None => throw(error)
      }
    }
  // Its children go in another container, which the page's HTML doesn't have.
  | Portal => ()
  | Offscreen => fail(context, 6, "an internal element (Offscreen) reached the HTML renderer")
  }

and renderHost = (request, attempt, context, node) => {
  let tag: string = fromUnknown(node.elementType)
  if !RegExp.test(tagPattern, tag) {
    fail(context, 1, `"${tag}" isn't a tag name`)
  }
  if Common.Env.isDev {
    checkNesting(context, tag)
  }
  let props = toProps(node.props)
  let children = Element.childrenOf(node.props)
  let context = {
    ...context,
    ancestors: list{tag, ...context.ancestors},
    path: list{`<${tag}>`, ...context.path},
    selectValue: tag == "select" ? optionalString(props->Dict.get("value")) : context.selectValue,
  }
  writeMarkup(attempt, `<${tag}${attributes(context, tag, props)}>`)
  if voidElements->Array.includes(tag) {
    if Element.classify(children) != Empty {
      fail(context, 3, `a <${tag}> can't have children`)
    }
  } else {
    if rawTextElements->Array.includes(tag) && Element.classify(children) != Empty {
      fail(context, 4, `a <${tag}>'s content isn't HTML, so it can't be rendered from children`)
    }
    if tag == "textarea" {
      let text = switch optionalString(props->Dict.get("value")) {
      | Some(value) => value
      | None => textOf(children)->Option.getOr("")
      }
      // The parser drops a newline straight after `<textarea>`: one more keeps the value's own.
      writeMarkup(attempt, (text->String.startsWith("\n") ? "\n" : "") ++ escapeText(text))
    } else {
      renderElement(request, attempt, context, children)
    }
    writeMarkup(attempt, `</${tag}>`)
  }
}

/**
A `Suspense` boundary. Its content is tried at once: if it's all ready, it's written in place;
if it fails, the boundary is failed (its fallback, for the client to render it again); if something
in it isn't ready, its fallback is written, and the content rendered later, in a segment of its own.
*/
and renderBoundary = (request, attempt, context, node) => {
  let props = toBoundaryProps(node.props)
  let context = {...context, path: list{"<Suspense>", ...context.path}}
  let content = newAttempt()
  switch renderElement(request, content, context, props.children) {
  | () if Array.length(content.pending) == 0 =>
    writeMarkup(attempt, "<!--$-->")
    content.buffer->Array.forEach(piece => attempt.buffer->Array.push(piece))
    content.spawns->Array.forEach(spawn => attempt.spawns->Array.push(spawn))
    writeMarkup(attempt, "<!--/$-->")
  | () if request.waitForAll =>
    // Nothing is left pending: the whole attempt waits.
    content.pending->Array.forEach(promise => attempt.pending->Array.push(promise))
  | () =>
    let spawn = {id: -1, children: props.children, context}
    writeMarkup(attempt, "<!--$?-->")
    attempt.buffer->Array.push(Anchor(spawn))
    renderElement(request, attempt, context, props.fallback)
    writeMarkup(attempt, "<!--/$-->")
    attempt.spawns->Array.push(spawn)
  | exception error =>
    writeMarkup(attempt, "<!--$!--><template")
    attempt.buffer->Array.push(Failure(error))
    writeMarkup(attempt, "></template>")
    renderElement(request, attempt, context, props.fallback)
    writeMarkup(attempt, "<!--/$-->")
  }
}

let maxAttempts = 100

let settled = (promise: promise<unknown>) =>
  promise->Promise.thenResolve(_ => ())->Promise.catch(_ => Promise.resolve())

exception Aborted

/** Renders `element` until nothing in it (outside pending boundaries) is waiting. */
let renderUntilReady = async (request, context, element) => {
  let result = ref(None)
  let attempts = ref(0)
  while Option.isNone(result.contents) {
    if request.aborted {
      throw(Aborted)
    }
    let attempt = newAttempt()
    renderElement(request, attempt, context, element)
    if Array.length(attempt.pending) == 0 {
      result := Some(attempt)
    } else {
      attempts := attempts.contents + 1
      if attempts.contents >= maxAttempts {
        fail(
          context,
          5,
          `the HTML suspended ${Int.toString(
              maxAttempts,
            )} times in a row (is a component making a new promise every time it's called?)`,
        )
      }
      let _ = await Promise.all(attempt.pending->Array.map(settled))
    }
  }
  Option.getUnsafe(result.contents)
}

/**
A kept attempt's HTML: its failed boundaries' errors are reported now, once, and its pending
boundaries given their ids (so this comes before starting them).
*/
let html = (request, attempt) =>
  attempt.buffer
  ->Array.map(piece =>
    switch piece {
    | Markup(markup) => markup
    | Failure(error) => errorAttributes(report(request, error))
    | Anchor(spawn) =>
      spawn.id = request.nextBoundary
      request.nextBoundary = spawn.id + 1
      `<template id="wb:${Int.toString(spawn.id)}"></template>`
    }
  )
  ->Array.join("")

type t = {shell: promise<string>, rest: stream}

let rootContext = {contexts: [], ancestors: list{}, selectValue: None, path: list{}}

let defaultOnError = error => {
  Console.error(error)
  None
}

let render = (element, ~onError=defaultOnError, ~signal=?) => {
  let request = {onError, waitForAll: false, nextBoundary: 0, aborted: false}
  let encoder = makeEncoder()
  let output = ref(None)
  let closed = ref(false)
  let wroteRuntime = ref(false)
  // Boundaries still being rendered, and whether the shell is done: the rest ends when both are.
  let running = ref(0)
  let shellDone = ref(false)
  let close = () =>
    if !closed.contents {
      closed := true
      output.contents->Option.forEach(controller =>
        try closeStream(controller) catch {
        | _ => ()
        }
      )
    }
  let finishIfDone = () =>
    if shellDone.contents && running.contents == 0 {
      close()
    }
  let emit = markup =>
    if !closed.contents && !request.aborted {
      let markup = if wroteRuntime.contents {
        markup
      } else {
        wroteRuntime := true
        `<script>${runtime}</script>` ++ markup
      }
      output.contents->Option.forEach(controller => controller->enqueue(encoder->encode(markup)))
    }
  let rest = makeStream({
    start: controller => output := Some(controller),
    cancel: _ => {
      request.aborted = true
      closed := true
    },
  })
  let rec start = spawns =>
    spawns->Array.forEach(spawn => {
      running := running.contents + 1
      let id = Int.toString(spawn.id)
      let run = async () => {
        switch await renderUntilReady(request, spawn.context, spawn.children) {
        | attempt =>
          let content = html(request, attempt)
          emit(`<template id="ws:${id}">${content}</template><script>$weftSwap(${id})</script>`)
          start(attempt.spawns)
        | exception Aborted => ()
        | exception error =>
          let (digest, message) = report(request, error)
          let argument = value => value->Option.mapOr("null", scriptString)
          emit(`<script>$weftFail(${id},${argument(digest)},${argument(message)})</script>`)
        }
        running := running.contents - 1
        finishIfDone()
      }
      run()->ignore
    })
  signal->Option.forEach(signal => {
    let abort = () => {
      request.aborted = true
      close()
    }
    isAborted(signal) ? abort() : signal->onAbort(abort, {once: true})
  })
  let shell = (
    async () => {
      switch await renderUntilReady(request, rootContext, element) {
      | attempt =>
        let shell = html(request, attempt)
        shellDone := true
        start(attempt.spawns)
        finishIfDone()
        shell
      | exception error =>
        shellDone := true
        close()
        switch error {
        | Aborted => ()
        | error => report(request, error)->ignore
        }
        throw(error)
      }
    }
  )()
  {shell, rest}
}

let shell = rendering => rendering.shell
let rest = rendering => rendering.rest

let renderToString = async (element, ~onError=defaultOnError) => {
  let request = {onError, waitForAll: true, nextBoundary: 0, aborted: false}
  html(request, await renderUntilReady(request, rootContext, element))
}

type reader
type readResult = {done: bool, value?: Uint8Array.t}
@send external getReader: stream => reader = "getReader"
@send external read: reader => promise<readResult> = "read"

let renderToStream = (element, ~onError=?, ~signal=?) => {
  let rendering = render(element, ~onError?, ~signal?)
  let encoder = makeEncoder()
  makeStream({
    start: controller => {
      let pipe = async () =>
        switch await rendering.shell {
        | shell =>
          controller->enqueue(encoder->encode(shell))
          let reader = rendering.rest->getReader
          let finished = ref(false)
          while !finished.contents {
            switch await reader->read {
            | {done: false, value} => controller->enqueue(value)
            | _ => finished := true
            }
          }
          controller->closeStream
        | exception JsExn(error) => controller->errorStream(toUnknown(error))
        | exception error => controller->errorStream(toUnknown(error))
        }
      pipe()->ignore
    },
  })
}
