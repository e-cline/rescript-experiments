@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The note's title, with a draft of a new one. The saved title and time are rendered on the server and
given as `children`: saving posts the draft, then refetches them (with `useRefetchable`), while the
draft (and the input, its focus and its selection) stays as it is.
*/

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~title: string, ~children: Weft.element) => {
  let (draft, setDraft) = Weft.Hooks.useState(() => title)
  let saved = WeftServer.Navigation.useRefetchable(~src=`/notes/${noteId}/title`, children)
  let save = event => {
    Weft.Dom.Event.preventDefault(event)

    (
      async () => {
        await Api.post(`/notes/${noteId}`, JSON.Encode.object(dict{"title": JSON.String(draft)}))
        await saved.refetch()
      }
    )()->ignore
  }
  <form id="editor" onSubmit=save>
    {saved.element}
    <input
      id="title-input"
      ariaLabel="Title"
      value=draft
      onInput={event => setDraft(_ => Weft.Dom.Event.targetValue(event))}
    />
    <button id="save" type_="submit">
      {Weft.Jsx.string(saved.isPending ? "Saving…" : "Save")}
    </button>
  </form>
}
