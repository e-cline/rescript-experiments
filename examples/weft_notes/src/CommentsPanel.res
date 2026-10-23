@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The comments (rendered on the server, and given as `children`), with a button that fetches them
again by themselves (`useRefetchable`), and says so while it's at it.
*/

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~children: Weft.element) => {
  let comments = WeftServer.Navigation.useRefetchable(~src=`/notes/${noteId}/comments`, children)
  <div id="comments-panel">
    <button
      id="reload-comments"
      title={comments.isPending ? "pending" : "idle"}
      onClick={_ => comments.refetch()->ignore}
    >
      {Weft.Jsx.string(comments.isPending ? "Reloading…" : "Reload comments")}
    </button>
    {comments.element}
  </div>
}
