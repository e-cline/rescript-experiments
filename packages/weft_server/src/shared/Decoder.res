module Element = WeftCore.Element
module Deferred = WeftCore.Deferred

type stream = Streams.t
type signal = Streams.Signal.t
type loadModule = string => promise<unknown>
type fetch = (string, ~signal: signal) => promise<stream>

type response = {ok: bool, status: int, body: Streams.t}
type fetchInit = {headers: dict<string>, signal: signal}
@val external globalFetch: (string, fetchInit) => promise<response> = "fetch"

let webFetch = async (url, ~signal) => {
  let response = await globalFetch(url, {headers: dict{"Accept": Payload.contentType}, signal})
  if !response.ok {
    Errors.fail(
      14,
      Common.Env.isDev
        ? `WeftServer: fetching ${url} failed with status ${Int.toString(response.status)}`
        : "",
    )
  }
  response.body
}

type t = {
  loadModule: loadModule,
  fetch: fetch,
  /** Each entrypoint file's module, by file id. */
  modules: Map.t<string, promise<unknown>>,
  /** Each entrypoint's component, by id. */
  components: Map.t<string, promise<unknown>>,
}

let make = (~loadModule, ~fetch=webFetch) => {
  loadModule,
  fetch,
  modules: Map.make(),
  components: Map.make(),
}

@get_index external field: (unknown, string) => Nullable.t<unknown> = ""

let notFound = (id, what) =>
  Errors.fail(12, Common.Env.isDev ? `WeftServer: the entrypoint ${id} has no ${what}` : "")

/** The component entrypoint `id` names: its file's module, then the modules inside to its `make`. */
let loadComponent = (client, id: string): promise<unknown> =>
  switch client.components->Map.get(id) {
  | Some(component) => component
  | None =>
    let (file, path) = switch id->String.indexOf("#") {
    | -1 => (id, "")
    | hash => (id->String.slice(~start=0, ~end=hash), id->String.slice(~start=hash + 1))
    }
    let module_ = switch client.modules->Map.get(file) {
    | Some(module_) => module_
    | None =>
      let module_ = client.loadModule(file)
      client.modules->Map.set(file, module_)
      module_
    }
    let component = module_->Promise.thenResolve(module_ => {
      let inner =
        path
        ->String.split(".")
        ->Array.filter(name => name != "")
        ->Array.reduce(module_, (outer, name) =>
          // ReScript exports a module named like a JavaScript global (`Error`) as `$$Error`.
          switch field(outer, name)->Nullable.toOption {
          | Some(inner) => inner
          | None =>
            switch field(outer, "$$" ++ name)->Nullable.toOption {
            | Some(inner) => inner
            | None => notFound(id, `module ${name}`)
            }
          }
        )
      switch field(inner, "make")->Nullable.toOption {
      | Some(make) => make
      | None => notFound(id, "make")
      }
    })
    client.components->Map.set(id, component)
    component
  }

/** One payload being decoded. */
type session = {
  client: t,
  rows: Map.t<int, Deferred.t<unknown>>,
  /** The rows that have come in (an entrypoint's row settles later, once its module loads). */
  arrived: Set.t<int>,
  /** Each loaded entrypoint's component, by its `E` row. */
  entrypoints: Map.t<int, unknown>,
  /**
  Once the stream has ended: what a row that never arrived fails with. A row first referred to after
  that (by a row decoded late, once its entrypoints loaded) fails at once.
  */
  mutable ended: option<int => JsError.t>,
}

let row = (session, id) =>
  switch session.rows->Map.get(id) {
  | Some(row) => row
  | None =>
    let row = Deferred.make()
    session.rows->Map.set(id, row)
    session.ended->Option.forEach(failure => row.reject(failure(id)))
    row
  }

external toUnknown: 'a => unknown = "%identity"
external fromUnknown: unknown => 'a = "%identity"
external toElementPromise: promise<unknown> => promise<Element.t> = "%identity"
let undefined: unknown = %raw(`undefined`)

external jsExnToError: JsExn.t => JsError.t = "%identity"

/** `error` as a JS error, to reject a row with: itself if it is one. */
let toJsError = (error: exn) =>
  switch error {
  | JsExn(error) => jsExnToError(error)
  | _ => JsError.make(Values.describeError(error))
  }

let unexpected = text =>
  Errors.fail(15, Common.Env.isDev ? `WeftServer: ${text} isn't a value in a payload` : "")

@get external childrenField: unknown => unknown = "children"

let rec decode = (session, json: JSON.t): unknown =>
  switch json {
  | Null => toUnknown(Nullable.null)
  | Boolean(value) => toUnknown(value)
  | Number(value) => toUnknown(value)
  | String(text) =>
    switch Payload.decodeString(text) {
    | Literal(text) => toUnknown(text)
    | Undefined => undefined
    | LazyRow(id) =>
      toUnknown(WeftCore.Lazy.fromPromise(toElementPromise(row(session, id).promise)))
    | PromiseRow(id) => toUnknown(row(session, id).promise)
    | Number(value) => toUnknown(value)
    | BigInt(value) => toUnknown(value)
    | Date(value) => toUnknown(value)
    | EntrypointType(_) | SuspenseType | FragmentType => unexpected(text)
    }
  | Array(items) =>
    switch Payload.asElement(items) {
    | Some((elementType, key, props)) => decodeElement(session, elementType, key, props)
    | None =>
      let decoded = items->Array.map(item => decode(session, item))
      // The server checked the lists it wrote for keys (`Render`): no need to again.
      WeftCore.JsxCore.markStaticList(fromUnknown(toUnknown(decoded)))
      toUnknown(decoded)
    }
  | Object(fields) => toUnknown(fields->Dict.mapValues(value => decode(session, value)))
  }

and decodeElement = (session, elementType, key, props): unknown => {
  let props = decode(session, props)
  let key = Nullable.toOption(key)
  // Children written as a list in the server's JSX were written there, not built at runtime: they
  // don't need keys, so they're passed on as `jsxs` marks them, without key warnings.
  let static = Array.isArray(childrenField(props))
  let component = (make: unknown) =>
    static
      ? WeftCore.JsxCore.jsxsKeyed(fromUnknown(make), props, ~key?, ())
      : WeftCore.JsxCore.jsxKeyed(fromUnknown(make), props, ~key?, ())
  let element = switch elementType {
  | JSON.String(text) =>
    switch Payload.decodeString(text) {
    | Literal(tag) =>
      static
        ? WeftCore.JsxCore.hostJsxsKeyed(tag, props, ~key?, ())
        : WeftCore.JsxCore.hostJsxKeyed(tag, props, ~key?, ())
    | SuspenseType => component(toUnknown(WeftCore.Suspense.make))
    | FragmentType => component(toUnknown(WeftCore.JsxCore.Fragment.make))
    | EntrypointType(id) =>
      switch session.entrypoints->Map.get(id) {
      | Some(make) => component(make)
      | None => unexpected(text)
      }
    | _ => unexpected(text)
    }
  | _ => unexpected(JSON.stringify(elementType))
  }
  toUnknown(element)
}

/** The `E` rows a model's elements refer to. */
let rec entrypointRows = (json: JSON.t, found: array<int>) =>
  switch json {
  | Array(items) =>
    switch Payload.asElement(items) {
    | Some((JSON.String(text), _, props)) =>
      switch Payload.decodeString(text) {
      | EntrypointType(id) => found->Array.push(id)
      | _ => ()
      }
      entrypointRows(props, found)
    | _ => items->Array.forEach(item => entrypointRows(item, found))
    }
  | Object(fields) => fields->Dict.forEach(value => entrypointRows(value, found))
  | _ => ()
  }

@get_index external jsonField: (JSON.t, string) => Nullable.t<JSON.t> = ""
@set external setDigest: (JsError.t, string) => unit = "digest"
@set external setFromPayload: (JsError.t, bool) => unit = "weftFromPayload"

let errorOf = (json: JSON.t) => {
  let text = field => jsonField(json, field)->Nullable.toOption->Option.flatMap(JSON.Decode.string)
  let error = JsError.make(
    switch text("message") {
    | Some(message) => message
    | None => "WeftServer: the server failed to render this"
    },
  )
  text("digest")->Option.forEach(digest => setDigest(error, digest))
  setFromPayload(error, true)
  error
}

@get external fromPayload: JsExn.t => Nullable.t<bool> = "weftFromPayload"
@get external digestOf: JsExn.t => Nullable.t<string> = "digest"

let reportedDigest = (error: exn) =>
  switch error {
  | JsExn(error) if fromPayload(error)->Nullable.toOption == Some(true) =>
    Some(digestOf(error)->Nullable.toOption)
  | _ => None
  }

let handleRow = (session, {id, tag, json}: Payload.row) => {
  session.arrived->Set.add(id)
  let target = row(session, id)
  switch tag {
  | Error => target.reject(errorOf(json))
  | EntrypointRef =>
    let entrypoint = switch jsonField(json, "id")
    ->Nullable.toOption
    ->Option.flatMap(JSON.Decode.string) {
    | Some(entrypoint) => entrypoint
    | None => unexpected(JSON.stringify(json))
    }
    loadComponent(session.client, entrypoint)
    ->Promise.thenResolve(component => {
      session.entrypoints->Map.set(id, component)
      target.resolve(component)
    })
    ->Promise.catch(error => {
      target.reject(toJsError(error))
      Promise.resolve()
    })
    ->ignore
  | Model =>
    let waitingFor = []
    entrypointRows(json, waitingFor)
    let missing = waitingFor->Array.filter(id => !(session.entrypoints->Map.has(id)))
    if Array.length(missing) == 0 {
      switch decode(session, json) {
      | value => target.resolve(value)
      | exception error => target.reject(toJsError(error))
      }
    } else {
      Promise.all(missing->Array.map(id => row(session, id).promise))
      ->Promise.thenResolve(_ => target.resolve(decode(session, json)))
      ->Promise.catch(error => {
        target.reject(toJsError(error))
        Promise.resolve()
      })
      ->ignore
    }
  }
}

let ended = id =>
  JsError.make(
    Common.Env.isDev
      ? `WeftServer: the payload ended before its row ${Int.toString(id)} arrived`
      : Errors.message(13, ""),
  )

/** Reads `stream` to its end, settling each row as it arrives. */
let read = async (session, stream, ~signal) => {
  let reader = stream->Streams.getReader
  signal->Option.forEach(signal =>
    signal->Streams.Signal.onAbort(
      () => reader->Streams.Reader.cancel->Promise.catch(_ => Promise.resolve())->ignore,
      {once: true},
    )
  )
  let decoder = Streams.Decoder.make()
  let parser = Payload.Parser.make()
  let finished = ref(false)
  let failure = ref(None)
  while !finished.contents {
    switch await reader->Streams.Reader.read {
    | {done: true} => finished := true
    | {value} =>
      let text = decoder->Streams.Decoder.decode(value, {stream: true})
      switch Payload.Parser.push(parser, text)->Array.forEach(row => handleRow(session, row)) {
      | () => ()
      | exception error =>
        failure := Some(error)
        finished := true
        reader->Streams.Reader.cancel->Promise.catch(_ => Promise.resolve())->ignore
      }
    | _ => finished := true
    | exception error =>
      failure := Some(error)
      finished := true
    }
  }
  // Aborted (a newer fetch replaced this one, say): what never arrived is left waiting, not failed,
  // since what's waiting on it may still be on screen until whatever replaces it is ready. The root
  // is the exception (below).
  let aborted = signal->Option.mapOr(false, Streams.Signal.aborted)
  // Otherwise, whatever never arrived won't now: it fails with what stopped the stream, if anything
  // did.
  let failure = id =>
    switch failure.contents {
    | Some(error) => toJsError(error)
    | None => ended(id)
    }
  if aborted {
    // Except the root: whoever's waiting for the element is told it isn't coming.
    if !(session.arrived->Set.has(0)) {
      row(session, 0).reject(failure(0))
    }
  } else {
    session.ended = Some(failure)
    session.rows->Map.forEachWithKey((row, id) =>
      if !(session.arrived->Set.has(id)) {
        row.reject(failure(id))
      }
    )
  }
}

let valueFromStream = (client, stream, ~signal=?) => {
  let session = {
    client,
    rows: Map.make(),
    arrived: Set.make(),
    entrypoints: Map.make(),
    ended: None,
  }
  let root = row(session, 0)
  read(session, stream, ~signal)->ignore
  root.promise
}

let fromStream = (client, stream, ~signal=?) =>
  valueFromStream(client, stream, ~signal?)->Promise.thenResolve((value): Element.t =>
    fromUnknown(value)
  )

let fetchElement = async (client, url, ~signal=?) => {
  let signal = switch signal {
  | Some(signal) => signal
  | None => Streams.Controller.make()->Streams.Controller.signal
  }
  let stream = await client.fetch(url, ~signal)
  await fromStream(client, stream, ~signal)
}

module Latest = {
  type client = t
  type t = {mutable latest: int, mutable controller: option<Streams.Controller.t>}

  let make = () => {latest: 0, controller: None}

  let fetchElement = async (latest, client, url) => {
    latest.latest = latest.latest + 1
    let mine = latest.latest
    latest.controller->Option.forEach(Streams.Controller.abort)
    let controller = Streams.Controller.make()
    latest.controller = Some(controller)
    let isLatest = () => mine == latest.latest
    switch await fetchElement(client, url, ~signal=Streams.Controller.signal(controller)) {
    | element => isLatest() ? Some(element) : None
    | exception error => isLatest() ? throw(error) : None
    }
  }
}
