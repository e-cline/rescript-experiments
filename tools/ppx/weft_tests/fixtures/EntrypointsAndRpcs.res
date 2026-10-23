@@jsxConfig({version: 4, module_: "Weft.TestJsx"})

/*** A file of entrypoints that declares an RPC too: both directives. */

@weft.rpc({id: "likes.like"})
let like: WeftServer.Rpc.t<string, string, int, unit> = WeftServer.Rpc.make(
  ~request=WeftServer.Rpc.Codec.string,
)

@weft.component({kind: Entrypoint})
let make = (~count: int) => Weft.TestJsx.string(Int.toString(count))
