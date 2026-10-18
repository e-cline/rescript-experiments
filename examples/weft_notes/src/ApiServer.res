@@weft.server

/***
The handlers of the RPCs `Api` declares, and the router that answers them (mounted in `Server`).
Server only: `@@weft.server` keeps the client from importing this file, or `Db`.
*/

module Rpc = WeftServer.Rpc

let saveTitle = Rpc.handler(Api.saveTitle, async ({noteId, title}, ~http as _) =>
  switch Db.find(noteId) {
  | Some(_) =>
    Db.saveTitle(noteId, title)
    Ok()
  | None => Error(Api.NoSuchNote)
  }
)

let addComment = Rpc.handler(Api.addComment, async ({noteId, author, text}, ~http as _) =>
  switch Db.find(noteId) {
  | Some(_) =>
    let id = Db.addComment(noteId, ~author, ~text)
    Ok({Types.id, author, text})
  | None => Error(Api.NoSuchNote)
  }
)

let like = Rpc.handler(Api.like, async (noteId, ~http as _) =>
  switch Db.find(noteId) {
  | Some(_) =>
    Db.like(noteId)
    Ok(Db.find(noteId)->Option.mapOr(0, note => note.likes))
  | None => Error(Api.NoSuchNote)
  }
)

/** What `/_weft/rpc/<id>` answers: these RPCs, and no others. */
let router = Rpc.router([saveTitle, addComment, like], ~onError=error => {
  Console.error(`weft_notes: an RPC failed: ${WeftCore.ErrorBoundary.message(error)}`)
  None
})
