@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The note's title, with a draft of a new one. Saving posts the draft, then refetches the frame it's
in (the header's): the saved title and time come back as new props, while the draft (and the input, its focus
and its selection) stay as they are.
*/

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~title: string, ~savedAt: string) => {
  let (draft, setDraft) = Weft.Hooks.useState(() => title)
  let header = WeftServer.Navigation.useFrame()
  let save = event => {
    Weft.Dom.Event.preventDefault(event)

    (
      async () => {
        await Api.post(`/notes/${noteId}`, JSON.Encode.object(dict{"title": JSON.String(draft)}))
        await header.refetch()
      }
    )()->ignore
  }
  <form id="editor" onSubmit=save>
    <h1 id="title"> {Weft.Jsx.string(title)} </h1>
    <input
      id="title-input"
      ariaLabel="Title"
      value=draft
      onInput={event => setDraft(_ => Weft.Dom.Event.targetValue(event))}
    />
    <button id="save" type_="submit">
      {Weft.Jsx.string(header.isPending ? "Saving…" : "Save")}
    </button>
    <span id="saved-at"> {Weft.Jsx.string(`Saved: ${savedAt}`)} </span>
  </form>
}
