@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The likes, from the server, and whether you just liked it, which is this button's own state: it
survives the page being fetched again, or another note's page in the same place.
*/

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~likes: int) => {
  let (justLiked, setJustLiked) = Weft.Hooks.useState(() => false)
  <button
    id="like"
    onClick={_ => {
      setJustLiked(_ => true)
      Api.post(`/notes/${noteId}/like`, JSON.Null)->ignore
    }}
  >
    {Weft.Jsx.string(`${Int.toString(likes)} likes${justLiked ? " (you liked this)" : ""}`)}
  </button>
}
