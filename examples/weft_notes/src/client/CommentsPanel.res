/***
The comments (rendered on the server, and given as `children`), with a button that fetches them
again by themselves (`useRefetchable`), and says so while it's at it.
*/

open WeftCss

module Styles = {
  let panel = Css.class({display: Grid, gap: Px(8)})
  /** The reload button: small, at the start of its row, dimmed while it's at it. */
  let reload = Css.class({
    justifySelf: Start,
    fontSize: Rem(0.875),
    padding: Pair(Px(2), Px(8)),
    selectors: [("&[title=\"pending\"]", Css.style({opacity: 0.6}))],
  })
}

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~children: Weft.Element.t) => {
  let comments = WeftServer.Navigation.useRefetchable(~src=`/notes/${noteId}/comments`, children)
  <div id="comments-panel" className=Styles.panel>
    <button
      id="reload-comments"
      className=Styles.reload
      title={comments.isPending ? "pending" : "idle"}
      onClick={_ => comments.refetch()->ignore}
    >
      {WeftDom.Jsx.string(comments.isPending ? "Reloading…" : "Reload comments")}
    </button>
    {comments.element}
  </div>
}
