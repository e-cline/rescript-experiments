/***
The notes, in memory: the app's "database". The queries the page streams (a note's body, its
comments, related notes) each wait on a gate (`Gates`); the rest answer at once.
*/

open Types

let notes: dict<note> = Dict.make()
let comments: dict<array<comment>> = Dict.make()
let revision = ref(0)

let seed = () => {
  notes->Dict.keysToArray->Array.forEach(key => notes->Dict.delete(key))
  comments->Dict.keysToArray->Array.forEach(key => comments->Dict.delete(key))
  revision := 0
  [
    {id: "1", title: "Groceries", body: "Milk, eggs, bread.", savedAt: "never", likes: 3},
    {
      id: "2",
      title: "Ideas",
      body: "A notes app with server components.",
      savedAt: "never",
      likes: 5,
    },
    {id: "3", title: "Reading", body: "The plan, then the code.", savedAt: "never", likes: 0},
  ]->Array.forEach(note => notes->Dict.set(note.id, note))
  comments->Dict.set("1", [{id: "c1", author: "Ada", text: "Don't forget coffee."}])
  comments->Dict.set("2", [{id: "c2", author: "Grace", text: "Ship it."}])
}

seed()

let all = () => notes->Dict.valuesToArray->Array.toSorted((a, b) => String.compare(a.id, b.id))
let find = id => notes->Dict.get(id)

let body = async (id, ~signal) => {
  await Gates.wait(`body:${id}`, ~signal)
  find(id)->Option.mapOr("", note => note.body)
}

let commentsOf = async (id, ~signal) => {
  await Gates.wait(`comments:${id}`, ~signal)
  comments->Dict.get(id)->Option.getOr([])
}

let related = async (id, ~signal) => {
  await Gates.wait(`related:${id}`, ~signal)
  all()->Array.filter(note => note.id != id)
}

let saveTitle = (id, title) =>
  find(id)->Option.forEach(note => {
    revision := revision.contents + 1
    notes->Dict.set(id, {...note, title, savedAt: `revision ${Int.toString(revision.contents)}`})
  })

let addComment = (noteId, ~author, ~text) => {
  let existing = comments->Dict.get(noteId)->Option.getOr([])
  let id = `c${Int.toString(Array.length(comments->Dict.valuesToArray->Array.flat) + 1)}`
  comments->Dict.set(noteId, [...existing, {id, author, text}])
  id
}

let editComment = (noteId, commentId, text) =>
  comments->Dict.set(
    noteId,
    comments
    ->Dict.get(noteId)
    ->Option.getOr([])
    ->Array.map(comment => comment.id == commentId ? {...comment, text} : comment),
  )

let setLikes = (id, likes) =>
  find(id)->Option.forEach(note => notes->Dict.set(id, {...note, likes}))
let like = id =>
  find(id)->Option.forEach(note => notes->Dict.set(id, {...note, likes: note.likes + 1}))
