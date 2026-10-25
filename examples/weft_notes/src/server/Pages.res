/***
The server components: the list of notes, and a note's page, with three parts that stream in on
their own (the body, the comments, related notes), two that entrypoints fetch again by themselves
(the saved title, the comments), and a
part that fails, inside an error box.

Every query is given the request's `signal`, so one that's still waiting when the client goes away
stops.
*/

open WeftCss

module Styles = {
  let app = Css.class({maxWidth: Px(720), margin: Pair(Zero, Auto), padding: Pair(Px(24), Px(16))})
  let nav = Css.class({
    display: Flex,
    justifyContent: SpaceBetween,
    alignItems: Baseline,
    paddingBottom: Px(12),
    marginBottom: Px(24),
    borderBottom: Theme.hairline(),
  })
  let homeLink = Css.class({fontWeight: 600, textDecoration: None})
  let title = Css.class({marginBottom: Px(16)})
  let noteLink = Css.class({
    fontWeight: 500,
    textDecoration: None,
    hover: Css.style({textDecoration: Underline}),
  })
  let header = Css.class({marginBottom: Px(16)})
  let savedAt = Css.class({display: Block, marginTop: Px(4)})
  let body = Css.class({margin: Pair(Px(16), Zero), lineHeight: 1.7, whiteSpace: PreLine})
  let section = Css.class({
    marginTop: Px(32),
    paddingTop: Px(16),
    borderTop: Theme.hairline(),
    display: Grid,
    gap: Px(12),
  })
  /** The related notes: a row of chips. */
  let related = Css.class({
    display: Flex,
    flexWrap: Wrap,
    gap: Px(8),
    listStyle: None,
    padding: Zero,
    margin: Pair(Px(24), Zero),
  })
  let chip = Css.class({
    display: InlineBlock,
    padding: Pair(Px(2), Px(10)),
    border: Theme.hairline(),
    borderRadius: Px(999),
    textDecoration: None,
    fontSize: Rem(0.875),
    hover: Css.style({borderColor: Var(Theme.accent)}),
  })
}

module Layout = {
  @weft.component({kind: Server})
  let make = (~children) =>
    <div dataId="app" className=Styles.app>
      <nav className=Styles.nav>
        <Link dataId="home-link" className=Styles.homeLink href="/">
          {WeftDom.Jsx.string("All notes")}
        </Link>
        <Today />
      </nav>
      children
    </div>
}

module NoteList = {
  @weft.component({kind: Server})
  let make = () =>
    <Layout>
      <h1 dataId="list-title" className=Styles.title> {WeftDom.Jsx.string("Notes")} </h1>
      <ul dataId="notes" className=Theme.list>
        {Db.all()
        ->Array.map(note =>
          <li key=note.id>
            <Link
              dataId={`note-link-${note.id}`} className=Styles.noteLink href={`/notes/${note.id}`}
            >
              {WeftDom.Jsx.string(note.title)}
            </Link>
          </li>
        )
        ->WeftDom.Jsx.array}
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
        <h1 dataId="title"> {WeftDom.Jsx.string(note.title)} </h1>
        <span dataId="saved-at" className={Css.cx([Styles.savedAt, Theme.secondary])}>
          {WeftDom.Jsx.string(`Saved: ${note.savedAt}`)}
        </span>
      </>
    | None => <p dataId="not-found" className=Theme.error> {WeftDom.Jsx.string("No such note")} </p>
    }
}

module NoteHeader = {
  /** The title, and the editor around it. */
  @weft.component({kind: Server})
  let make = (~id) =>
    <header dataId="note-header" className=Styles.header>
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
    <article dataId="note-body" className=Styles.body> {WeftDom.Jsx.string(body)} </article>
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
    <ul dataId="related" className=Styles.related>
      {notes
      ->Array.map(note =>
        <li key=note.id>
          <Link dataId={`related-${note.id}`} className=Styles.chip href={`/notes/${note.id}`}>
            {WeftDom.Jsx.string(note.title)}
          </Link>
        </li>
      )
      ->WeftDom.Jsx.array}
    </ul>
  }
}

module Broken = {
  /** Fails, every time: its error is shown by the error box around it, and nothing else. */
  @weft.component({kind: Server})
  let make = () => JsError.throwWithMessage("the recommendations service is down")
}

let loading = (id, text) => <p dataId=id className=Theme.loading> {WeftDom.Jsx.string(text)} </p>

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
      <section dataId="comments-section" className=Styles.section>
        <h2> {WeftDom.Jsx.string("Comments")} </h2>
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
