/***
A stand-in for a database: notes kept in memory. One store is shared by the
whole application, so every request sees the same notes.
*/

type note = {
  id: int,
  text: string,
  author: string,
}

type t = {mutable notes: array<note>}

let make = () => {notes: []}

let all = store => store.notes

let add = (store, ~text, ~author) => {
  let note = {id: store.notes->Array.length + 1, text, author}
  store.notes = store.notes->Array.concat([note])
  note
}

let toJson = note =>
  JSON.Encode.object(
    dict{
      "id": JSON.Encode.int(note.id),
      "text": JSON.Encode.string(note.text),
      "author": JSON.Encode.string(note.author),
    },
  )
