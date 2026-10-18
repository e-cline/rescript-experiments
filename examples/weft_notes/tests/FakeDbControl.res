/***
What the tests do to the server, through `WeftTesting.callServer`: these run in the server's
worker, on the same `Gates` and `Db` the app uses. (Test-only, so the app itself has no test hooks.)
*/

/** Every gate closed, nothing waiting, and the notes as they started. */
let reset = () => {
  Gates.reset()
  Db.seed()
}

let release = gate => Gates.release(gate)
let waiting = () => Gates.waiting()
let abandoned = () => Gates.abandoned->Array.copy

/** Another user, adding a comment. Returns its id. */
let addComment = (noteId, author, text) => Db.addComment(noteId, ~author, ~text)

let editComment = (noteId, commentId, text) => Db.editComment(noteId, commentId, text)
let setLikes = (noteId, likes) => Db.setLikes(noteId, likes)
let title = noteId => Db.find(noteId)->Option.mapOr("", note => note.title)
