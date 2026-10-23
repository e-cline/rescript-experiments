/***
The RPCs the entrypoints call, declared here, in shared code: each one's ID, how its request goes
over the wire, and what's checked before it's sent. Their handlers are in `ApiServer`, which only
the server has.
*/

module Rpc = WeftServer.Rpc
module Codec = WeftServer.Rpc.Codec

/** What an RPC can say no with. */
type error =
  | EmptyTitle
  | EmptyComment
  | TooLong
  | NoSuchNote

/** What to tell the user. */
let message = error =>
  switch error {
  | EmptyTitle => "A title can't be empty."
  | EmptyComment => "Write something first."
  | TooLong => "That's too long: 500 characters at most."
  | NoSuchNote => "This note doesn't exist any more."
  }

/** The longest a title or a comment can be. */
let maxLength = 500

let notTooLong = text => String.length(text) > maxLength ? Error(TooLong) : Ok()

type saveTitle = {noteId: string, title: string}

@weft.rpc({id: "notes.saveTitle"})
let saveTitle: Rpc.t<saveTitle, saveTitle, unit, error> = Rpc.makePrepared(
  ~request=Codec.object2(
    ("noteId", Codec.string),
    ("title", Codec.string),
    (noteId, title) => {noteId, title},
    ({noteId, title}) => (noteId, title),
  ),
  ~prepare=async ({noteId, title}) => Ok({noteId, title: String.trim(title)}),
  ~check=({title}) => title == "" ? Error(EmptyTitle) : notTooLong(title),
)

type addComment = {noteId: string, author: string, text: string}

@weft.rpc({id: "notes.addComment"})
let addComment: Rpc.t<addComment, addComment, Types.comment, error> = Rpc.makePrepared(
  ~request=Codec.object3(
    ("noteId", Codec.string),
    ("author", Codec.string),
    ("text", Codec.string),
    (noteId, author, text) => {noteId, author, text},
    ({noteId, author, text}) => (noteId, author, text),
  ),
  // On the client, before anything's sent: an empty comment goes nowhere.
  ~prepare=async ({noteId, author, text}) =>
    switch String.trim(text) {
    | "" => Error(EmptyComment)
    | text =>
      Ok({
        noteId,
        author: switch String.trim(author) {
        | "" => "Anonymous"
        | author => author
        },
        text,
      })
    },
  // On both sides: the server can't count on the client to have.
  ~check=({text}) => text == "" ? Error(EmptyComment) : notTooLong(text),
)

@weft.rpc({id: "notes.like"})
let like: Rpc.t<string, string, int, error> = Rpc.make(~request=Codec.string)

/** What to tell the user when a call fails. */
let describe = (error: Rpc.error<error>) =>
  switch error {
  | Rejected(error) => message(error)
  | Invalid(_) => "The server couldn't read that: reload the page, and try again."
  | Failed(_) => "Something went wrong: try again."
  }
