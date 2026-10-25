/***
The likes, from the server, and whether you just liked it (liking is the `notes.like` RPC), which is this button's own state: it
survives the page being fetched again, or another note's page in the same place.
*/

open WeftCss

module Styles = {
  let like = Css.class({
    borderRadius: Px(999),
    padding: Pair(Px(4), Px(14)),
    color: Var(Theme.accent),
    borderColor: Var(Theme.accent),
  })
}

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~likes: int) => {
  let (justLiked, setJustLiked) = Weft.Hooks.useState(() => false)
  let like = WeftServer.Rpc.use(Api.like)
  <button
    dataId="like"
    className=Styles.like
    onClick={_ => {
      setJustLiked(_ => true)
      like(noteId)->ignore
    }}
  >
    {WeftDom.Jsx.string(`${Int.toString(likes)} likes${justLiked ? " (you liked this)" : ""}`)}
  </button>
}
