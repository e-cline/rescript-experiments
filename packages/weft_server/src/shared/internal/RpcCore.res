/***
What `Rpc` (declaring and calling RPCs, on both sides) and `RpcServer` (answering them, on the server)
share: the declaration's record and the wire's constants. `Rpc.t` is a private alias of `t`, so
`RpcServer` can read a declaration, and only `Rpc.make` can build one.
*/

type t<'input, 'request, 'response, 'error> = {
  id: string,
  request: RpcCodec.t<'request>,
  prepare: option<'input => promise<result<'request, 'error>>>,
  check: option<'request => result<unit, 'error>>,
  maxBytes: option<int>,
}

/** The root of a response's payload: what the handler answered, or why there's no answer. */
let kindOk = "ok"
let kindError = "error"
let kindInvalid = "invalid"

let rpcHeader = "x-weft-rpc"

let defaultBase = "/_weft/rpc"

let defaultMaxBytes = 65536
