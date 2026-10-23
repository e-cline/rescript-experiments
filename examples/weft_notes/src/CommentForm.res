@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
Posts a comment (the `notes.addComment` RPC), then fetches the page again to show it. The author
stays filled in; the text is cleared. If the RPC says no (an empty comment, which never leaves the
browser, or one the server refuses), it says why. The comment's input is described by a hint, linked
by an ID from `useId` (the same in the server's HTML as once hydrated).
*/

@weft.component({kind: Entrypoint})
let make = (~noteId: string) => {
  let (author, setAuthor) = Weft.Hooks.useState(() => "")
  let (text, setText) = Weft.Hooks.useState(() => "")
  let (error, setError) = Weft.Hooks.useState(() => None)
  let hintId = Weft.Hooks.useId()
  let navigation = WeftServer.Navigation.useNavigation()
  let addComment = WeftServer.Rpc.use(Api.addComment)
  let submit = event => {
    Weft.Dom.Event.preventDefault(event)

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
  <form id="comment-form" onSubmit=submit>
    <input
      id="comment-author"
      ariaLabel="Name"
      value=author
      onInput={event => setAuthor(_ => Weft.Dom.Event.targetValue(event))}
    />
    <input
      id="comment-text"
      ariaLabel="Comment"
      ariaDescribedby=hintId
      value=text
      onInput={event => setText(_ => Weft.Dom.Event.targetValue(event))}
    />
    <p id=hintId className="hint">
      {Weft.Jsx.string(`At most ${Int.toString(Api.maxLength)} characters.`)}
    </p>
    <button id="post-comment" type_="submit"> {Weft.Jsx.string("Post")} </button>
    {switch error {
    | Some(message) => <p id="comment-error" role="alert"> {Weft.Jsx.string(message)} </p>
    | None => Weft.Jsx.null
    }}
  </form>
}
