@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
Posts a comment, then fetches the page again to show it. The author stays filled in; the text is
cleared.
*/

@weft.component({kind: Entrypoint})
let make = (~noteId: string) => {
  let (author, setAuthor) = Weft.Hooks.useState(() => "")
  let (text, setText) = Weft.Hooks.useState(() => "")
  let navigation = WeftServer.Navigation.useNavigation()
  let submit = event => {
    Weft.Dom.Event.preventDefault(event)

    (
      async () => {
        await Api.post(
          `/notes/${noteId}/comments`,
          JSON.Encode.object(dict{"author": JSON.String(author), "text": JSON.String(text)}),
        )
        setText(_ => "")
        await navigation->WeftServer.Navigation.refresh
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
      value=text
      onInput={event => setText(_ => Weft.Dom.Event.targetValue(event))}
    />
    <button id="post-comment" type_="submit"> {Weft.Jsx.string("Post")} </button>
  </form>
}
