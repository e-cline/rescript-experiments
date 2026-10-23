@@directive("'use weft server'")

module Element = WeftCore.Element

type signal = Streams.Signal.t
type stream = Streams.t

/** One payload being written. */
type request = {
  controller: Streams.controller,
  encoder: Streams.Encoder.t,
  mutable nextId: int,
  /** Rows allocated but not yet written: the stream ends when this reaches 0. */
  mutable pending: int,
  mutable aborted: bool,
  mutable closed: bool,
  mutable buffer: array<string>,
  mutable flushScheduled: bool,
  /** The `E` row written for each entrypoint id. */
  entrypoints: Map.t<string, int>,
  onError: exn => option<string>,
}

/** Where in the tree the encoder is. */
type context = {
  request: request,
  /** Whether a `Suspense` boundary is above: if so, pending work becomes a row of its own. */
  inSuspense: bool,
  /** For messages: how the encoder got here, innermost first. */
  path: list<string>,
  /** The arrays and objects being encoded, to find cycles. */
  ancestors: list<unknown>,
}

// Writing rows

let flush = request =>
  if !request.closed && Array.length(request.buffer) > 0 {
    let text = request.buffer->Array.join("")
    request.buffer = []
    request.controller->Streams.enqueue(request.encoder->Streams.Encoder.encode(text))
  }

let close = request =>
  if !request.closed {
    flush(request)
    request.closed = true
    request.controller->Streams.close
  }

let abort = request =>
  if !request.closed {
    request.aborted = true
    request.closed = true
    // Cancelling the stream has already closed it, so this can throw; it's closed either way.
    try request.controller->Streams.close catch {
    | _ => ()
    }
  }

let scheduleFlush = request =>
  if !request.flushScheduled {
    request.flushScheduled = true
    Streams.setTimeout(() => {
      request.flushScheduled = false
      flush(request)
    }, 0)
  }

let write = (request, row: Payload.row) =>
  if !request.aborted && !request.closed {
    request.buffer->Array.push(Payload.rowToString(row))
    scheduleFlush(request)
  }

let allocate = request => {
  let id = request.nextId
  request.nextId = id + 1
  request.pending = request.pending + 1
  id
}

let finish = request => {
  request.pending = request.pending - 1
  if request.pending == 0 {
    close(request)
  }
}

let errorJson = (request, error: exn): JSON.t => {
  let digest = try request.onError(error) catch {
  | _ => None
  }
  let fields = dict{}
  digest->Option.forEach(digest => fields->Dict.set("digest", JSON.Encode.string(digest)))
  if Common.Env.isDev {
    fields->Dict.set("message", JSON.Encode.string(Values.describeError(error)))
  }
  JSON.Encode.object(fields)
}

/** Writes row `id` once `work` has its model, or an error row if it fails. */
let spawn = (context, id, work: unit => promise<JSON.t>) => {
  let request = context.request
  let run = async () => {
    let row: Payload.row = switch await work() {
    | json => {id, tag: Model, json}
    | exception error => {id, tag: Error, json: errorJson(request, error)}
    }
    write(request, row)
    finish(request)
  }
  run()->ignore
}

// Messages

let where = context =>
  switch context.path {
  | list{} => "the root"
  | path => path->List.reverse->List.toArray->Array.join("")
  }

let fail = (context, code, message) =>
  Errors.fail(code, Common.Env.isDev ? `WeftServer: ${message}, at ${where(context)}` : "")

let enter = (context, segment) => {...context, path: list{segment, ...context.path}}

let enterObject = (context, value) => {
  if context.ancestors->List.some(ancestor => ancestor === value) {
    fail(context, 6, "a value can't contain itself (a cycle) when it's sent from the server")
  }
  {...context, ancestors: list{value, ...context.ancestors}}
}

// The encoder

let maxRetries = 100

external toComponent: unknown => unknown => Element.t = "%identity"
external toNode: unknown => Element.node = "%identity"

type suspenseProps = {fallback: Element.t, children: Element.t}
external toSuspenseProps: unknown => suspenseProps = "%identity"

/** The warnings given so far, so each is given once. */
let warned: Set.t<string> = Set.make()

@get external nodeKey: unknown => Nullable.t<string> = "key"

/**
Warns (in development) about a list of children built at runtime (`Jsx.array`), not written out in
JSX, in which some elements have no key, as the reconciler would if it rendered it: the client
doesn't check the lists it decodes, since the server wrote them.
*/
let checkKeys = (context, value: unknown) => {
  let isChildList = switch context.path {
  | list{".children", ..._} | list{_, ".children", ..._} => true
  | _ => false
  }
  let items: array<unknown> = Values.fromUnknown(value)
  if (
    isChildList &&
    Array.length(items) > 1 &&
    !WeftCore.JsxCore.isStaticList(Values.fromUnknown(value)) &&
    items->Array.some(item => Values.isElementNode(item) && Nullable.isNullable(nodeKey(item)))
  ) {
    let message = `WeftCore: Each child in a list should have a unique "key" prop. The list at ${where(
        context,
      )} (rendered on the server) has children without one.`
    if !(warned->Set.has(message)) {
      warned->Set.add(message)
      Console.error(message)
    }
  }
}

let rec encodeValue = async (context, value: unknown): JSON.t =>
  switch Type.typeof(value) {
  | #undefined => Payload.undefined
  | #boolean => JSON.Encode.bool(Values.fromUnknown(value))
  | #number => Payload.number(Values.fromUnknown(value))
  | #string => Payload.string(Values.fromUnknown(value))
  | #bigint => Payload.bigint(Values.fromUnknown(value))
  | #function =>
    fail(
      context,
      2,
      "a function can't be sent from the server (an entrypoint's props come from it, serialized)",
    )
  | #symbol => fail(context, 5, "a symbol can't be sent from the server")
  | #object =>
    if Values.isNull(value) {
      JSON.Encode.null
    } else if Array.isArray(value) {
      if Common.Env.isDev {
        checkKeys(context, value)
      }
      let context = enterObject(context, value)
      let items: array<unknown> = Values.fromUnknown(value)
      JSON.Encode.array(
        await Promise.all(
          items->Array.mapWithIndex((item, index) =>
            encodeValue(enter(context, `[${Int.toString(index)}]`), item)
          ),
        ),
      )
    } else if Values.isElementNode(value) {
      await encodeNode(context, toNode(value))
    } else if Values.isThenable(value) {
      encodePromise(context, Values.fromUnknown(value))
    } else if Values.isDate(value) {
      Payload.date(Values.fromUnknown(value))
    } else if Values.isPlainObject(value) {
      let context = enterObject(context, value)
      await encodeFields(context, value, ~field=(context, _, value) => encodeValue(context, value))
    } else {
      fail(
        context,
        5,
        "only plain values (strings, numbers, booleans, records, variants, arrays, dicts, dates, elements and promises) can be sent from the server, not an instance of a class",
      )
    }
  }

/** An object's fields, each encoded by `field`. Fields that are `undefined` are left out. */
and encodeFields = async (context, value, ~field) => {
  let names =
    Values.keys(value)->Array.filter(name => Type.typeof(Values.get(value, name)) != #undefined)
  let encoded = await Promise.all(
    names->Array.map(name => field(enter(context, `.${name}`), name, Values.get(value, name))),
  )
  JSON.Encode.object(
    Dict.fromArray(
      names->Array.mapWithIndex((name, index) => (name, encoded->Array.getUnsafe(index))),
    ),
  )
}

and encodePromise = (context, promise: promise<unknown>): JSON.t => {
  let id = allocate(context.request)
  // What it resolves to may itself have parts that aren't ready: they stream, like a boundary's.
  spawn({...context, inSuspense: true}, id, async () =>
    await encodeValue({...context, inSuspense: true}, await promise)
  )
  Payload.promiseRow(id)
}

and encodeNode = async (context, node: Element.node): JSON.t =>
  switch node.kind {
  | Host =>
    let tag: string = Values.fromUnknown(node.elementType)
    let context = enter(context, `<${tag}>`)
    let props = await encodeFields(context, node.props, ~field=(context, name, value) =>
      if name == "ref" {
        fail(
          context,
          4,
          "a host element rendered on the server can't have a ref: render it in an entrypoint",
        )
      } else if name->String.startsWith("on") && Type.typeof(value) == #function {
        fail(
          context,
          3,
          "a host element rendered on the server can't have an event handler: render it in an entrypoint",
        )
      } else {
        encodeValue(context, value)
      }
    )
    Payload.element(~elementType=Payload.string(tag), ~key=node.key, ~props)
  | Component | Memo =>
    let make = toComponent(node.elementType)
    let context = enter(context, `<${Values.componentName(node.elementType)}>`)
    switch WeftCore.Entrypoint.idOf(make) {
    | Some(id) =>
      let row = entrypointRow(context, id)
      Payload.element(
        ~elementType=Payload.entrypointType(row),
        ~key=node.key,
        ~props=await encodeValue(context, node.props),
      )
    | None =>
      let encode = async () => {
        let output = await renderComponent(context, make, node.props)
        // The component leaves no fiber on the client, so its key goes on its output.
        switch Nullable.toOption(node.key) {
        | Some(_) =>
          Payload.element(
            ~elementType=Payload.fragmentType,
            ~key=node.key,
            ~props=JSON.Encode.object(dict{"children": output}),
          )
        | None => output
        }
      }
      if context.inSuspense {
        switch await encode() {
        | json => json
        | exception error => errorRow(context, error)
        }
      } else {
        await encode()
      }
    }
  | Fragment =>
    Payload.element(
      ~elementType=Payload.fragmentType,
      ~key=node.key,
      ~props=JSON.Encode.object(
        dict{
          "children": await encodeValue(context, Values.toUnknown(Element.childrenOf(node.props))),
        },
      ),
    )
  | Suspense =>
    let props = toSuspenseProps(node.props)
    let context = enter(context, "<Suspense>")
    let (fallback, children) = await Promise.all2((
      encodeValue(enter(context, ".fallback"), Values.toUnknown(props.fallback)),
      encodeValue(
        {...enter(context, ".children"), inSuspense: true},
        Values.toUnknown(props.children),
      ),
    ))
    Payload.element(
      ~elementType=Payload.suspenseType,
      ~key=node.key,
      ~props=JSON.Encode.object(dict{"fallback": fallback, "children": children}),
    )
  | Lazy =>
    if context.inSuspense {
      switch await pending(context, () => WeftCore.Lazy.promiseOf(node)) {
      | json => json
      | exception error => errorRow(context, error)
      }
    } else {
      await pending(context, () => WeftCore.Lazy.promiseOf(node))
    }
  | Provider =>
    fail(
      context,
      7,
      "a context provider can't be rendered on the server (context doesn't reach server components): render it in an entrypoint",
    )
  | ErrorBoundary =>
    fail(
      context,
      8,
      "an ErrorBoundary can't be rendered on the server (its fallback is a function): render it in an entrypoint",
    )
  | Portal =>
    fail(context, 9, "a portal can't be rendered on the server: render it in an entrypoint")
  | Offscreen => fail(context, 11, "an internal element (Offscreen) reached the server renderer")
  }

/** What `make` rendered, encoded, calling it again whenever it suspends. */
and renderComponent = async (context, make, props): JSON.t => {
  let call = () =>
    switch WeftCore.ServerRender.run(() => make(props)) {
    | element => Ok(element)
    | exception error =>
      switch WeftCore.ServerRender.suspendedOn(error) {
      | Some(promise) => Error(promise)
      | None => throw(error)
      }
    }
  switch call() {
  | Ok(element) => await encodeValue(context, Values.toUnknown(element))
  | Error(promise) =>
    await pending(context, async () => {
      let suspendedOn = ref(promise)
      let output = ref(None)
      let attempts = ref(1)
      while Option.isNone(output.contents) {
        // Its outcome doesn't matter here: calling again rethrows a rejection.
        switch await suspendedOn.contents {
        | _ => ()
        | exception _ => ()
        }
        if context.request.aborted {
          // Nothing will be written; this just ends the loop.
          output := Some(Element.null)
        } else {
          switch call() {
          | Ok(element) => output := Some(element)
          | Error(promise) =>
            attempts := attempts.contents + 1
            if attempts.contents > maxRetries {
              fail(
                context,
                10,
                `a component suspended ${Int.toString(
                    maxRetries,
                  )} times in a row (is it making a new promise every time it's called?)`,
              )
            }
            suspendedOn := promise
          }
        }
      }
      Option.getUnsafe(output.contents)
    })
  }
}

/**
Something that isn't ready: waited for here outside every `Suspense`; under one, a placeholder,
with the content in a row of its own once `wait` has it.
*/
and pending = async (context, wait: unit => promise<Element.t>): JSON.t =>
  if context.inSuspense {
    let id = allocate(context.request)
    spawn(context, id, async () => await encodeValue(context, Values.toUnknown(await wait())))
    Payload.lazyRow(id)
  } else {
    await encodeValue(context, Values.toUnknown(await wait()))
  }

/** An error under a `Suspense` boundary: an error row, and a placeholder pointing at it. */
and errorRow = (context, error) => {
  let request = context.request
  let id = allocate(request)
  write(request, {id, tag: Error, json: errorJson(request, error)})
  finish(request)
  Payload.lazyRow(id)
}

/** The row of the `E` reference for entrypoint `id`, written the first time it's needed. */
and entrypointRow = (context, id) => {
  let request = context.request
  switch request.entrypoints->Map.get(id) {
  | Some(row) => row
  | None =>
    let row = allocate(request)
    request.entrypoints->Map.set(id, row)
    write(
      request,
      {id: row, tag: EntrypointRef, json: JSON.Encode.object(dict{"id": JSON.Encode.string(id)})},
    )
    finish(request)
    row
  }
}

let defaultOnError = error => {
  Console.error(error)
  None
}

let valueToStream = (value: unknown, ~onError=defaultOnError, ~signal=?) => {
  let request = ref(None)
  Streams.make({
    start: controller => {
      let current = {
        controller,
        encoder: Streams.Encoder.make(),
        nextId: 0,
        pending: 0,
        aborted: false,
        closed: false,
        buffer: [],
        flushScheduled: false,
        entrypoints: Map.make(),
        onError,
      }
      request := Some(current)
      switch signal {
      | Some(signal) if Streams.Signal.aborted(signal) => abort(current)
      | Some(signal) => signal->Streams.Signal.onAbort(() => abort(current), {once: true})
      | None => ()
      }
      let context = {request: current, inSuspense: false, path: list{}, ancestors: list{}}
      let root = allocate(current)
      spawn(context, root, () => encodeValue(context, value))
    },
    cancel: _ => request.contents->Option.forEach(abort),
  })
}

let toStream = (element: Element.t, ~onError=?, ~signal=?) =>
  valueToStream(Values.toUnknown(element), ~onError?, ~signal?)
