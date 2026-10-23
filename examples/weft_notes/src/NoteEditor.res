@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

/***
The note's title, with a draft of a new one. The saved title and time are rendered on the server and
given as `children`: saving sends the draft (the `notes.saveTitle` RPC), then refetches them (with
`useRefetchable`), while the draft (and the input, its focus and its selection) stays as it is.
*/

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~title: string, ~children: Weft.Element.t) => {
  let (draft, setDraft) = Weft.Hooks.useState(() => title)
  let (error, setError) = Weft.Hooks.useState(() => None)
  let saved = WeftServer.Navigation.useRefetchable(~src=`/notes/${noteId}/title`, children)
  let saveTitle = WeftServer.Rpc.use(Api.saveTitle)
  let save = event => {
    WeftDom.Dom.Event.preventDefault(event)

    (
      async () => {
        switch await saveTitle({noteId, title: draft}) {
        | Ok() =>
          setError(_ => None)
          await saved.refetch()
        | Error(error) => setError(_ => Some(Api.describe(error)))
        }
      }
    )()->ignore
  }
  <form id="editor" onSubmit=save>
    {saved.element}
    <input
      id="title-input"
      ariaLabel="Title"
      value=draft
      onInput={event => setDraft(_ => WeftDom.Dom.Event.targetValue(event))}
    />
    <button id="save" type_="submit">
      {WeftDom.Jsx.string(saved.isPending ? "Saving…" : "Save")}
    </button>
    {switch error {
    | Some(message) => <p id="title-error" role="alert"> {WeftDom.Jsx.string(message)} </p>
    | None => WeftDom.Jsx.null
    }}
  </form>
}
