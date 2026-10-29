/***
The server components: the list of notes, and a note's page, with three parts that stream in on
their own (the body, the comments, related notes), two that entrypoints fetch again by themselves
(the saved title, the comments), and a
part that fails, inside an error box.

Every query is given the request's `signal`, so one that's still waiting when the client goes away
stops.
*/

open WeftCss
module Ui = WeftUi
module Jsx = WeftDom.Jsx

let text = Jsx.string

module Styles = {
  let app = Css.class({paddingBlock: Px(24)})
  /** The related notes: a row of chips. */
  let related = Css.class({flexDirection: Row, flexWrap: Wrap, marginBlock: Px(8)})
  let nav = Css.class({
    paddingBlock: Px(12),
    marginBlockEnd: Px(24),
    borderBottom: Theme.hairline(),
  })
  let body = Css.class({margin: Zero, lineHeight: 1.7, whiteSpace: PreLine})
  let section = Css.class({marginTop: Px(16), paddingTop: Px(16), borderTop: Theme.hairline()})
}

module Layout = {
  @weft.component({kind: Server})
  let make = (~children) =>
    <Ui.Container size=#md dataId="app" className={Css.cx([Theme.root, Styles.app])}>
      <nav className=Styles.nav>
        <Ui.Stack direction=#row justify=#between align=#baseline>
          <Link
            dataId="home-link"
            className={Ui.Link.className(~tone=#inherit, ~underline=#hover, ())}
            href="/"
          >
            <Ui.Text as_=#span weight=#semibold> {text("All notes")} </Ui.Text>
          </Link>
          <Today />
        </Ui.Stack>
      </nav>
      children
    </Ui.Container>
}

module NoteList = {
  @weft.component({kind: Server})
  let make = () =>
    <Layout>
      <Ui.Stack gap=#lg>
        <Ui.Heading level=#h1 dataId="list-title"> {text("Notes")} </Ui.Heading>
        <Ui.List.Root divided=true dataId="notes">
          {Db.all()
          ->Array.map(note =>
            <Ui.List.Item key=note.id>
              <Link
                dataId={`note-link-${note.id}`}
                className={Ui.Link.className(~tone=#inherit, ~underline=#hover, ())}
                href={`/notes/${note.id}`}
              >
                <Ui.Text as_=#span weight=#medium> {text(note.title)} </Ui.Text>
              </Link>
            </Ui.List.Item>
          )
          ->Jsx.array}
        </Ui.List.Root>
      </Ui.Stack>
    </Layout>
}

module NoteTitle = {
  /** The note's title and when it was saved, which `NoteEditor` fetches again after a save. */
  @weft.component({kind: Server})
  let make = (~id) =>
    switch Db.find(id) {
    | Some(note) =>
      <Ui.Stack gap=#xs>
        <Ui.Heading level=#h1 dataId="title"> {text(note.title)} </Ui.Heading>
        <Ui.Text as_=#span tone=#muted size=#sm dataId="saved-at">
          {text(`Saved: ${note.savedAt}`)}
        </Ui.Text>
      </Ui.Stack>
    | None => <Ui.Text tone=#danger dataId="not-found"> {text("No such note")} </Ui.Text>
    }
}

module NoteHeader = {
  /** The title, and the editor around it. */
  @weft.component({kind: Server})
  let make = (~id) =>
    <header dataId="note-header">
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
    <div>
      <LikeButton noteId=id likes={Db.find(id)->Option.mapOr(0, note => note.likes)} />
    </div>
  }
}

module NoteBody = {
  @weft.component({kind: Server})
  let make = async (~id, ~signal) => {
    let body = await Db.body(id, ~signal)
    <article dataId="note-body" className=Styles.body> {Jsx.string(body)} </article>
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
    <Ui.List.Root gap=#sm dataId="related" className=Styles.related ariaLabel="Related notes">
      {notes
      ->Array.map(note =>
        <Ui.List.Item key=note.id>
          <Link
            dataId={`related-${note.id}`}
            className={Ui.Badge.className(~variant=#outline, ~link=true, ())}
            href={`/notes/${note.id}`}
          >
            {text(note.title)}
          </Link>
        </Ui.List.Item>
      )
      ->Jsx.array}
    </Ui.List.Root>
  }
}

module Broken = {
  /** Fails, every time: its error is shown by the error box around it, and nothing else. */
  @weft.component({kind: Server})
  let make = () => JsError.throwWithMessage("the recommendations service is down")
}

let loading = (id, message) =>
  <Ui.Text dataId=id tone=#muted italic=true> {text(message)} </Ui.Text>

module NotePage = {
  @weft.component({kind: Server})
  let make = (~id, ~signal) =>
    <Layout>
      <Ui.Stack gap=#lg>
        <NoteHeader id />
        <Weft.Suspense fallback={loading("likes-loading", "…")}>
          <Likes id />
        </Weft.Suspense>
        <Weft.Suspense fallback={loading("body-loading", "Loading the note…")}>
          <NoteBody id signal />
        </Weft.Suspense>
        <section dataId="comments-section" className=Styles.section ariaLabelledby="comments-title">
          <Ui.Stack gap=#md>
            <Ui.Heading level=#h2 size=#lg id="comments-title"> {text("Comments")} </Ui.Heading>
            <CommentsPanel noteId=id>
              <Comments id signal />
            </CommentsPanel>
            <CommentForm noteId=id />
          </Ui.Stack>
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
      </Ui.Stack>
    </Layout>
}
