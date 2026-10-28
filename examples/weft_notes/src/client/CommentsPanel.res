/***
The comments (rendered on the server, and given as `children`), with a button that fetches them
again by themselves (`useRefetchable`), and says so while it's at it.
*/

module Ui = WeftUi
module Jsx = WeftDom.Jsx

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~children: Weft.Element.t) => {
  let comments = WeftServer.Navigation.useRefetchable(~src=`/notes/${noteId}/comments`, children)
  <Ui.Stack gap=#sm dataId="comments-panel" align=#start>
    <Ui.Button
      dataId="reload-comments"
      size=#sm
      title={comments.isPending ? "pending" : "idle"}
      onClick={_ => comments.refetch()->ignore}
    >
      {Jsx.string(comments.isPending ? "Reloading…" : "Reload comments")}
    </Ui.Button>
    <div ariaBusy={comments.isPending ? "true" : "false"}> {comments.element} </div>
  </Ui.Stack>
}
