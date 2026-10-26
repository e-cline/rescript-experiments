/***
The note's title, with a draft of a new one. The saved title and time are rendered on the server and
given as `children`: saving sends the draft (the `notes.saveTitle` RPC), then refetches them (with
`useRefetchable`), while the draft (and the input, its focus and its selection) stays as it is. If
the RPC says no, it says why: about the title (empty, too long) on its field, anything else at the
form's top.
*/

open WeftCss
module Ui = WeftUi

module Styles = {
  /** The draft and its button, side by side, the button at the input's foot. */
  let row = Css.class({display: Flex, flexWrap: Wrap, gap: Px(8), alignItems: End})
  let input = Css.class({flex: "1 1 16rem"})
}

type error = Title(string) | Form(string)

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~title: string, ~children: Weft.Element.t) => {
  let (draft, setDraft) = Weft.Hooks.useState(() => title)
  let (error, setError) = Weft.Hooks.useState(() => None)
  let saved = WeftServer.Navigation.useRefetchable(~src=`/notes/${noteId}/title`, children)
  let saveTitle = WeftServer.Rpc.use(Api.saveTitle)
  let save = () =>
    (
      async () => {
        switch await saveTitle({noteId, title: draft}) {
        | Ok() =>
          setError(_ => None)
          await saved.refetch()
        | Error(Rejected(EmptyTitle | TooLong) as error) =>
          setError(_ => Some(Title(Api.describe(error))))
        | Error(error) => setError(_ => Some(Form(Api.describe(error))))
        }
      }
    )()->ignore
  <Ui.Form
    dataId="editor"
    onSubmit=save
    error=?{switch error {
    | Some(Form(message)) => Some(message)
    | _ => None
    }}
  >
    <div ariaBusy={saved.isPending ? "true" : "false"}> {saved.element} </div>
    <div className=Styles.row>
      <Ui.Field
        label="Title"
        hideLabel=true
        className=Styles.input
        error=?{switch error {
        | Some(Title(message)) => Some(message)
        | _ => None
        }}
      >
        <Ui.Input
          dataId="title-input"
          value=draft
          onInput={event => setDraft(_ => WeftDom.Dom.Event.targetValue(event))}
        />
      </Ui.Field>
      <Ui.Button dataId="save" type_=#submit busy=saved.isPending>
        {WeftDom.Jsx.string(saved.isPending ? "Saving…" : "Save")}
      </Ui.Button>
    </div>
  </Ui.Form>
}
