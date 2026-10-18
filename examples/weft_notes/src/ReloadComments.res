@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/*** Reloads the comments' frame, and says so while it's at it. */

@weft.component({kind: Entrypoint})
let make = () => {
  let comments = WeftServer.Navigation.useFrame("comments")
  <button
    id="reload-comments"
    title={comments.isPending ? "pending" : "idle"}
    onClick={_ => comments.refetch()->ignore}
  >
    {Weft.Jsx.string(comments.isPending ? "Reloading…" : "Reload comments")}
  </button>
}
