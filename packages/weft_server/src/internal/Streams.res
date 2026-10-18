/***
The Web stream, text encoding and abort APIs the renderer and the client use: a few bindings rather
than a dependency on `@rescript/webapi`. Every runtime this targets (Node 22+, browsers, Deno, Bun,
workers) has them built in.
*/

/** A `ReadableStream` of bytes: what a payload is sent as. */
type t

/** A `ReadableStreamDefaultController`. */
type controller

type source = {
  start?: controller => unit,
  pull?: controller => promise<unit>,
  cancel?: unknown => unit,
}

@new external make: source => t = "ReadableStream"
@send external enqueue: (controller, Uint8Array.t) => unit = "enqueue"
@send external close: controller => unit = "close"
@send external error: (controller, unknown) => unit = "error"

module Reader = {
  type t
  type result = {done: bool, value?: Uint8Array.t}
  @send external read: t => promise<result> = "read"
  @send external cancel: t => promise<unit> = "cancel"
}

@send external getReader: t => Reader.t = "getReader"

module Encoder = {
  type t
  @new external make: unit => t = "TextEncoder"
  @send external encode: (t, string) => Uint8Array.t = "encode"
}

module Decoder = {
  type t
  type options = {stream: bool}
  @new external make: unit => t = "TextDecoder"
  @send external decode: (t, Uint8Array.t, options) => string = "decode"
  /** What's left of a character split across chunks, once the stream ends. */
  @send external finish: t => string = "decode"
}

module Signal = {
  /** An `AbortSignal`. */
  type t
  @get external aborted: t => bool = "aborted"
  type listenerOptions = {once: bool}
  @send
  external onAbort: (t, @as("abort") _, unit => unit, listenerOptions) => unit = "addEventListener"
}

module Controller = {
  /** An `AbortController`. */
  type t
  @new external make: unit => t = "AbortController"
  @get external signal: t => Signal.t = "signal"
  @send external abort: t => unit = "abort"
}

@val external setTimeout: (unit => unit, int) => unit = "setTimeout"
