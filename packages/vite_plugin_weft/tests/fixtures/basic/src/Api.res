/*** RPCs, declared in a shared file: the scan collects their IDs. */

@weft.rpc({id: "basic.save"})
let save: WeftServer.Rpc.t<string, string, unit, unit> = WeftServer.Rpc.make(
  ~request=WeftServer.Rpc.Codec.string,
)

@weft.rpc({id: "basic.remove"})
let remove: WeftServer.Rpc.t<int, int, unit, unit> = WeftServer.Rpc.make(
  ~request=WeftServer.Rpc.Codec.int,
)
