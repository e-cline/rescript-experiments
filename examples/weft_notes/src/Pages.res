@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The server components: the list of notes, and a note's page, with three parts that stream in on
their own (the body, the comments, related notes), two that entrypoints fetch again by themselves
(the saved title, the comments), and a
part that fails, inside an error box.

Every query is given the request's `signal`, so one that's still waiting when the client goes away
stops.
*/

module Layout = {
  @weft.component({kind: Server})
  let make = (~children) =>
    <div id="app">
      <nav>
        <Link id="home-link" href="/"> {Weft.Jsx.string("All notes")} </Link>
        <Today />
      </nav>
      children
    </div>
}

module NoteList = {
  @weft.component({kind: Server})
  let make = () =>
    <Layout>
      <h1 id="list-title"> {Weft.Jsx.string("Notes")} </h1>
      <ul id="notes">
        {Db.all()
        ->Array.map(note =>
          <li key=note.id>
            <Link id={`note-link-${note.id}`} href={`/notes/${note.id}`}>
              {Weft.Jsx.string(note.title)}
            </Link>
          </li>
        )
        ->Weft.Jsx.array}
      </ul>
    </Layout>
}

module NoteTitle = {
  /** The note's title and when it was saved, which `NoteEditor` fetches again after a save. */
  @weft.component({kind: Server})
  let make = (~id) =>
    switch Db.find(id) {
    | Some(note) =>
      <>
        <h1 id="title"> {Weft.Jsx.string(note.title)} </h1>
        <span id="saved-at"> {Weft.Jsx.string(`Saved: ${note.savedAt}`)} </span>
      </>
    | None => <p id="not-found"> {Weft.Jsx.string("No such note")} </p>
    }
}

module NoteHeader = {
  /** The title, and the editor around it. */
  @weft.component({kind: Server})
  let make = (~id) =>
    <header id="note-header">
      <NoteEditor noteId=id title={Db.find(id)->Option.mapOr("", note => note.title)}>
        <NoteTitle id />
      </NoteEditor>
    </header>
}

module Likes = {
  /** The like button, in a row of its own (so the page doesn't wait for its chunk). */
  @weft.component({kind: Server})
  let make = async (~id) => {
    await Promise.resolve()
    <LikeButton noteId=id likes={Db.find(id)->Option.mapOr(0, note => note.likes)} />
  }
}

module NoteBody = {
  @weft.component({kind: Server})
  let make = async (~id, ~signal) => {
    let body = await Db.body(id, ~signal)
    <article id="note-body"> {Weft.Jsx.string(body)} </article>
  }
}

module Comments = {
  /** The list, given the comments as a promise: what `CommentsPanel` fetches again. */
  @weft.component({kind: Server})
  let make = (~id, ~signal) => <CommentList comments={Db.commentsOf(id, ~signal)} />
}

module Related = {
  @weft.component({kind: Server})
  let make = async (~id, ~signal) => {
    let notes = await Db.related(id, ~signal)
    <ul id="related">
      {notes
      ->Array.map(note =>
        <li key=note.id>
          <Link id={`related-${note.id}`} href={`/notes/${note.id}`}>
            {Weft.Jsx.string(note.title)}
          </Link>
        </li>
      )
      ->Weft.Jsx.array}
    </ul>
  }
}

module Broken = {
  /** Fails, every time: its error is shown by the error box around it, and nothing else. */
  @weft.component({kind: Server})
  let make = () => JsError.throwWithMessage("the recommendations service is down")
}

let loading = (id, text) => <p id> {Weft.Jsx.string(text)} </p>

module NotePage = {
  @weft.component({kind: Server})
  let make = (~id, ~signal) =>
    <Layout>
      <NoteHeader id />
      <Weft.Suspense fallback={loading("likes-loading", "…")}>
        <Likes id />
      </Weft.Suspense>
      <Weft.Suspense fallback={loading("body-loading", "Loading the note…")}>
        <NoteBody id signal />
      </Weft.Suspense>
      <section id="comments-section">
        <h2> {Weft.Jsx.string("Comments")} </h2>
        <CommentsPanel noteId=id>
          <Comments id signal />
        </CommentsPanel>
        <CommentForm noteId=id />
      </section>
      <Weft.Suspense fallback={loading("related-loading", "Finding related notes…")}>
        <Related id signal />
      </Weft.Suspense>
      // A boundary of its own around the error box: the server's error is thrown again on the
      // client, for the box to catch, and the part rendered on the client to show it is this
      // boundary, not the whole page.
      <Weft.Suspense fallback={loading("recommendations-loading", "…")}>
        <ErrorBox>
          <Weft.Suspense fallback={loading("broken-loading", "…")}>
            <Broken />
          </Weft.Suspense>
        </ErrorBox>
      </Weft.Suspense>
    </Layout>
}
