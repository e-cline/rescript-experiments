/***
A `ReadableStream` of bytes, which is what a streamed `Response` body is.

`@rescript/webapi` binds `ReadableStream` itself, but leaves what goes into
its constructor (the underlying source and its controller) and what comes out
of `getReader` typed as `unknown`. These are typed versions of those parts,
with `TextEncoder`/`TextDecoder`.
*/

type t = ReadableStream.t<Uint8Array.t>

/** A `ReadableStreamDefaultController`: how an underlying source feeds its stream. */
type controller

@send external enqueue: (controller, Uint8Array.t) => unit = "enqueue"
@send external close: controller => unit = "close"

/**
An underlying source. The stream calls `pull` whenever it wants another chunk,
and waits for the returned promise before calling it again, so a source that
enqueues one chunk per `pull` produces data only as fast as it's consumed.
`cancel` is called if the consumer goes away (e.g. the client disconnects).
*/
type source = {
  start?: controller => unit,
  pull?: controller => promise<unit>,
  cancel?: unknown => unit,
}

external toUnderlyingSource: source => FileTypes.underlyingSource<Uint8Array.t> = "%identity"

let make = (source: source): t => ReadableStream.fromUnderlyingSource(toUnderlyingSource(source))

/** How a stream came to an end. */
type ending =
  /** Everything was produced and read. */
  | Completed
  /** The consumer stopped reading: for a response, the client disconnected. */
  | Cancelled
  /** Producing a chunk failed. */
  | Failed(exn)

/**
A stream of the chunks `next` returns, ending at its first `None`. `next` is
called for one chunk at a time, only when the consumer is ready for more, and
not again after the consumer cancels.

`onEnd` is called once, when the stream is over, with how it ended. It's the
place to release whatever `next` was reading from, since it is called whether
the stream ran to its end, was cancelled, or failed.
*/
let fromPull = (
  ~onEnd: option<ending => unit>=?,
  next: unit => promise<option<Uint8Array.t>>,
): t => {
  let ended = ref(false)
  let finish = (ending: ending): unit =>
    if !ended.contents {
      ended := true
      onEnd->Option.forEach(onEnd => onEnd(ending))
    }
  make({
    pull: async controller =>
      switch await next() {
      | Some(chunk) => controller->enqueue(chunk)
      | None =>
        controller->close
        finish(Completed)
      | exception error =>
        finish(Failed(error))
        // Rethrown so that the stream fails, and its consumer finds out.
        throw(error)
      },
    cancel: _reason => finish(Cancelled),
  })
}

module Encoder = {
  type t

  @new external make: unit => t = "TextEncoder"

  /** Encodes a string as UTF-8. */
  @send
  external encode: (t, string) => Uint8Array.t = "encode"
}

module Decoder = {
  type t

  @new external make: unit => t = "TextDecoder"

  /** Decodes a whole UTF-8 byte sequence. */
  @send
  external decode: (t, Uint8Array.t) => string = "decode"

  type options = {stream: bool}

  @send external decodeWith: (t, Uint8Array.t, options) => string = "decode"

  /**
  Decodes the next part of a sequence that arrives in pieces. A character
  whose bytes are split between two pieces comes out with the second.
  */
  let decodeChunk = (decoder: t, chunk: Uint8Array.t): string =>
    decoder->decodeWith(chunk, {stream: true})
}

module Reader = {
  /** A `ReadableStreamDefaultReader`. */
  type t

  /** `value` is absent once `done` is true. */
  type result = {
    done: bool,
    value?: Uint8Array.t,
  }

  external fromUnknown: FileTypes.readableStreamReader<Uint8Array.t> => t = "%identity"

  @send external read: t => promise<result> = "read"

  /** Tells the stream's source that nothing more will be read. */
  @send
  external cancel: t => promise<unit> = "cancel"
}

let getReader = (stream: t): Reader.t => stream->ReadableStream.getReader->Reader.fromUnknown

/**
`Response.body` and `Request.body` are typed as streams of `array<int>`; their
chunks are really `Uint8Array`s.
*/
external fromBody: ReadableStream.t<array<int>> => t = "%identity"

/**
Reads a stream to its end, returning each chunk decoded as UTF-8 text. A
character split across two chunks is in the text of the second.
*/
let toTextChunks = async (stream: t): array<string> => {
  let reader = stream->getReader
  let decoder = Decoder.make()
  let chunks = []
  let finished = ref(false)
  while !finished.contents {
    switch await reader->Reader.read {
    | {done: false, value} => chunks->Array.push(decoder->Decoder.decodeChunk(value))
    | _ => finished := true
    }
  }
  chunks
}
