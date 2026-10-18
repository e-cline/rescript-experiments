/***
RPC declarations, in a shared file: `@weft.rpc` passes each its ID as `~id`, and the file gets a
`'use weft rpc <id>'` directive for each.
*/

type note = {id: string, title: string}

let noteCodec = WeftServer.Rpc.Codec.object2(
  ("id", WeftServer.Rpc.Codec.string),
  ("title", WeftServer.Rpc.Codec.string),
  (id, title) => {id, title},
  ({id, title}) => (id, title),
)

@weft.rpc({id: "notes.save"})
let save: WeftServer.Rpc.t<note, note, unit, string> = WeftServer.Rpc.make(~request=noteCodec)

module Nested = {
  @weft.rpc({id: "notes.rename_2"})
  let rename: WeftServer.Rpc.t<string, note, unit, string> = WeftServer.Rpc.makePrepared(
    ~request=noteCodec,
    ~prepare=async (title: string) => Ok({id: "1", title}),
    ~check=note => note.title == "" ? Error("empty") : Ok(),
  )
}

module Rpc = WeftServer.Rpc

@weft.rpc({id: "Billing.refund"})
let refund: Rpc.t<int, int, bool, unit> = Rpc.make(~request=Rpc.Codec.int)
