/***
Posts a comment (the `notes.addComment` RPC), then fetches the page again to show it. The author
stays filled in; the text is cleared. If the RPC says no (an empty comment, which never leaves the
browser, or one the server refuses), it says why. The comment's input is described by a hint, linked
by an ID from `useId` (the same in the server's HTML as once hydrated).
*/

open WeftCss

module Styles = {
  let form = Css.class({
    display: Grid,
    gridTemplateColumns: "minmax(8rem, 1fr) 3fr auto",
    gap: Px(8),
    alignItems: Center,
    media: [Css.media(~query="(max-width: 560px)", {gridTemplateColumns: "1fr"})],
  })
  /** The hint and the error: under the fields, across the row. */
  let note = Css.class({gridColumn: "1 / -1", margin: Zero})
  let post = Css.class({
    backgroundColor: Var(Theme.accent),
    borderColor: Var(Theme.accent),
    color: Named("white"),
    hover: Css.style({opacity: 0.9}),
  })
}

@weft.component({kind: Entrypoint})
let make = (~noteId: string) => {
  let (author, setAuthor) = Weft.Hooks.useState(() => "")
  let (text, setText) = Weft.Hooks.useState(() => "")
  let (error, setError) = Weft.Hooks.useState(() => None)
  let hintId = Weft.Hooks.useId()
  let navigation = WeftServer.Navigation.useNavigation()
  let addComment = WeftServer.Rpc.use(Api.addComment)
  let submit = event => {
    WeftDom.Dom.Event.preventDefault(event)

    (
      async () => {
        switch await addComment({noteId, author, text}) {
        | Ok(_) =>
          setError(_ => None)
          setText(_ => "")
          await navigation->WeftServer.Navigation.refresh
        | Error(error) => setError(_ => Some(Api.describe(error)))
        }
      }
    )()->ignore
  }
  <form dataId="comment-form" className=Styles.form onSubmit=submit>
    <input
      dataId="comment-author"
      ariaLabel="Name"
      value=author
      onInput={event => setAuthor(_ => WeftDom.Dom.Event.targetValue(event))}
    />
    <input
      dataId="comment-text"
      ariaLabel="Comment"
      ariaDescribedby=hintId
      value=text
      onInput={event => setText(_ => WeftDom.Dom.Event.targetValue(event))}
    />
    <button dataId="post-comment" className=Styles.post type_="submit">
      {WeftDom.Jsx.string("Post")}
    </button>
    <p id=hintId className={Css.cx([Styles.note, Theme.secondary])}>
      {WeftDom.Jsx.string(`At most ${Int.toString(Api.maxLength)} characters.`)}
    </p>
    {switch error {
    | Some(message) =>
      <p dataId="comment-error" className={Css.cx([Styles.note, Theme.error])} role="alert">
        {WeftDom.Jsx.string(message)}
      </p>
    | None => WeftDom.Jsx.null
    }}
  </form>
}
