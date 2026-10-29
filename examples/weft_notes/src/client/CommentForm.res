/***
Posts a comment (the `notes.addComment` RPC), then fetches the page again to show it. The author
stays filled in; the text is cleared. If the RPC says no, it says why: about the comment (empty,
which never leaves the browser, or too long, which the server checks again) on the comment's field,
anything else (the note's gone) at the form's top. The comment's hint describes its input, linked by
an ID from `useId` (the same in the server's HTML as once hydrated).
*/

module Ui = WeftUi
module Jsx = WeftDom.Jsx

/** What the RPC said no with: about the comment itself, or about the form as a whole. */
type error = Comment(string) | Form(string)

@weft.component({kind: Entrypoint})
let make = (~noteId: string) => {
  let (author, setAuthor) = Weft.Hooks.useState(() => "")
  let (text, setText) = Weft.Hooks.useState(() => "")
  let (error, setError) = Weft.Hooks.useState(() => None)
  let navigation = WeftServer.Navigation.useNavigation()
  let addComment = WeftServer.Rpc.use(Api.addComment)
  let submit = () =>
    (
      async () => {
        switch await addComment({noteId, author, text}) {
        | Ok(_) =>
          setError(_ => None)
          setText(_ => "")
          await navigation->WeftServer.Navigation.refresh
        | Error(Rejected(EmptyComment | TooLong) as error) =>
          setError(_ => Some(Comment(Api.describe(error))))
        | Error(error) => setError(_ => Some(Form(Api.describe(error))))
        }
      }
    )()->ignore
  <Ui.Form
    dataId="comment-form"
    onSubmit=submit
    error=?{switch error {
    | Some(Form(message)) => Some(message)
    | _ => None
    }}
  >
    <Ui.Grid template="minmax(8rem, 1fr) 3fr" stackBelow=#sm>
      <Ui.Field label="Name">
        <Ui.Input
          dataId="comment-author"
          value=author
          autoComplete="name"
          onInput={event => setAuthor(_ => WeftDom.Dom.Event.targetValue(event))}
        />
      </Ui.Field>
      <Ui.Field
        label="Comment"
        description={`At most ${Int.toString(Api.maxLength)} characters.`}
        error=?{switch error {
        | Some(Comment(message)) => Some(message)
        | _ => None
        }}
      >
        <Ui.Input
          dataId="comment-text"
          value=text
          onInput={event => setText(_ => WeftDom.Dom.Event.targetValue(event))}
        />
      </Ui.Field>
    </Ui.Grid>
    <Ui.Stack direction=#row>
      <Ui.Button dataId="post-comment" variant=#primary type_=#submit>
        {Jsx.string("Post")}
      </Ui.Button>
    </Ui.Stack>
  </Ui.Form>
}
