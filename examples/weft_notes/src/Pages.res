@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The server components: the list of notes, and a note's page, with three parts that stream in on
their own (the body, the comments, related notes), two frames (the header, the comments), and a
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

module NoteHeader = {
  /** The note's title and when it was saved: the header frame's content. */
  @weft.component({kind: Server})
  let make = (~id) =>
    switch Db.find(id) {
    | Some(note) =>
      <header id="note-header">
        <NoteEditor noteId=id title=note.title savedAt=note.savedAt />
      </header>
    | None => <p id="not-found"> {Weft.Jsx.string("No such note")} </p>
    }
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
  /**
  The comments' frame's content: the button that reloads them (inside the frame, so it finds it),
  and the list, given the comments as a promise.
  */
  @weft.component({kind: Server})
  let make = (~id, ~signal) => <>
    <ReloadComments />
    <CommentList comments={Db.commentsOf(id, ~signal)} />
  </>
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
      <WeftServer.Frame src={`/notes/${id}/header`}>
        <NoteHeader id />
      </WeftServer.Frame>
      <Weft.Suspense fallback={loading("likes-loading", "…")}>
        <Likes id />
      </Weft.Suspense>
      <Weft.Suspense fallback={loading("body-loading", "Loading the note…")}>
        <NoteBody id signal />
      </Weft.Suspense>
      <section id="comments-section">
        <h2> {Weft.Jsx.string("Comments")} </h2>
        <WeftServer.Frame src={`/notes/${id}/comments`}>
          <Comments id signal />
        </WeftServer.Frame>
        <CommentForm noteId=id />
      </section>
      <Weft.Suspense fallback={loading("related-loading", "Finding related notes…")}>
        <Related id signal />
      </Weft.Suspense>
      <ErrorBox>
        <Weft.Suspense fallback={loading("broken-loading", "…")}>
          <Broken />
        </Weft.Suspense>
      </ErrorBox>
    </Layout>
}
