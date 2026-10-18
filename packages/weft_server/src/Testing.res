type delivery =
  | Immediate
  | Manual

type chunking =
  | AsWritten
  | EveryBytes(int)

@get external byteLength: Uint8Array.t => int = "length"
@send external subarray: (Uint8Array.t, int, int) => Uint8Array.t = "subarray"

type state = {
  mutable controller: option<Streams.controller>,
  queue: array<Uint8Array.t>,
  mutable sourceDone: bool,
  mutable closed: bool,
  mutable written: string,
  finished: WeftCore.Deferred.t<unit>,
}

type pipe = {state: state, output: Streams.t}

let closeIfDone = state =>
  if state.sourceDone && Array.length(state.queue) == 0 && !state.closed {
    state.closed = true
    state.controller->Option.forEach(Streams.close)
  }

let send = (state, piece) =>
  if !state.closed {
    state.controller->Option.forEach(controller => controller->Streams.enqueue(piece))
  }

let pieces = (chunk, chunking) =>
  switch chunking {
  | AsWritten => [chunk]
  | EveryBytes(size) =>
    let size = Math.Int.max(size, 1)
    let length = byteLength(chunk)
    Array.fromInitializer(~length=(length + size - 1) / size, index =>
      chunk->subarray(index * size, Math.Int.min((index + 1) * size, length))
    )
  }

let pipe = (source, ~delivery=Immediate, ~chunking=AsWritten) => {
  let reader = source->Streams.getReader
  let state = {
    controller: None,
    queue: [],
    sourceDone: false,
    closed: false,
    written: "",
    finished: WeftCore.Deferred.make(),
  }
  let output = Streams.make({
    start: controller => state.controller = Some(controller),
    cancel: _ => {
      state.closed = true
      reader->Streams.Reader.cancel->ignore
    },
  })
  let decoder = Streams.Decoder.make()
  let pump = async () => {
    let done = ref(false)
    while !done.contents {
      switch await reader->Streams.Reader.read {
      | {done: false, value} =>
        state.written = state.written ++ decoder->Streams.Decoder.decode(value, {stream: true})
        pieces(value, chunking)->Array.forEach(piece =>
          switch delivery {
          | Immediate => send(state, piece)
          | Manual => state.queue->Array.push(piece)
          }
        )
      | _ => done := true
      | exception _ => done := true
      }
    }
    state.sourceDone = true
    closeIfDone(state)
    state.finished.resolve()
  }
  pump()->ignore
  {state, output}
}

let stream = pipe => pipe.output

let deliver = ({state}) =>
  switch state.queue->Array.shift {
  | Some(piece) =>
    send(state, piece)
    closeIfDone(state)
    true
  | None => false
  }

let deliverAll = pipe =>
  while deliver(pipe) {
    ()
  }

let waiting = ({state}) => Array.length(state.queue)
let finished = ({state}) => state.finished.promise
let written = ({state}) => state.written

let readAll = async stream => {
  let reader = stream->Streams.getReader
  let decoder = Streams.Decoder.make()
  let text = ref("")
  let done = ref(false)
  while !done.contents {
    switch await reader->Streams.Reader.read {
    | {done: false, value} =>
      text := text.contents ++ decoder->Streams.Decoder.decode(value, {stream: true})
    | _ => done := true
    }
  }
  text.contents
}

type modules = {
  byFile: Map.t<string, unknown>,
  loads: array<string>,
  mutable held: option<WeftCore.Deferred.t<unit>>,
}

let modules = entries => {byFile: Map.fromArray(entries), loads: [], held: None}

let module_ = (exports: array<(string, unknown)>): unknown =>
  Values.toUnknown(Dict.fromArray(exports))

external component: WeftCore.JsxCore.component<'props> => unknown = "%identity"

let notServed = file =>
  JsError.throwWithMessage(
    `WeftServer.Testing: no module for ${file} (it isn't in Testing.modules)`,
  )

let loadModule = (modules): Client.loadModule =>
  file => {
    modules.loads->Array.push(file)
    let load = () =>
      switch modules.byFile->Map.get(file) {
      | Some(module_) => module_
      | None => notServed(file)
      }
    switch modules.held {
    | Some(held) => held.promise->Promise.thenResolve(load)
    | None => Promise.resolve()->Promise.thenResolve(load)
    }
  }

let loads = modules => modules.loads

let hold = modules =>
  if Option.isNone(modules.held) {
    modules.held = Some(WeftCore.Deferred.make())
  }

let release = modules => {
  modules.held->Option.forEach(held => held.resolve())
  modules.held = None
}

let tick = () => Promise.make((resolve, _) => Streams.setTimeout(() => resolve(), 0))
