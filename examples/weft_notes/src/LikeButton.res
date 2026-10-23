@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/***
The likes, from the server, and whether you just liked it (liking is the `notes.like` RPC), which is this button's own state: it
survives the page being fetched again, or another note's page in the same place.
*/

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~likes: int) => {
  let (justLiked, setJustLiked) = Weft.Hooks.useState(() => false)
  let like = WeftServer.Rpc.use(Api.like)
  <button
    id="like"
    onClick={_ => {
      setJustLiked(_ => true)
      like(noteId)->ignore
    }}
  >
    {WeftDom.Jsx.string(`${Int.toString(likes)} likes${justLiked ? " (you liked this)" : ""}`)}
  </button>
}
