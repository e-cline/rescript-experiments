# weft_notes

A small notes app built with [Weft's server components](../../packages/weft_server), and the test
bed for them: every feature, tested the way a browser uses them, through
[`@e-cline/weft_vite_plugin`'s harness](../../tools/weft_vite_plugin#testing-an-app), and a few
things only a browser can show, in Chromium.

- The list of notes, and a note's page ([`src/server/Pages.res`](src/server/Pages.res)), with three
  parts that stream in on their own (the body, the comments, related notes), each under a `Suspense`
  boundary.
- `LikeButton`, an entrypoint with state of its own (whether you just liked it), whose count comes
  from the server.
- `NoteEditor`, a draft of the title in state, and the saved title and time, rendered on the server,
  as its `children`: saving sends the draft (an RPC), then refetches those (`useRefetchable`), while
  the draft, the input, its focus and its selection stay.
- The comments in `CommentsPanel`, an entrypoint that refetches them (`useRefetchable`) with a
  button, a `CommentList` entrypoint given them as a promise (and showing its own fallback until it
  resolves), and `CommentForm`, which posts a comment (an RPC) and then `refresh`es the page.
- Weft RPCs for every change: saving a title, adding a comment and liking, declared in
  [`src/shared/Api.res`](src/shared/Api.res) (each one's ID, codec, and the checks made before
  anything is sent) and handled in [`src/server/ApiServer.res`](src/server/ApiServer.res), a
  server-only file (`@@weft.server`, as are the database and its gates). Errors are the RPCs' own:
  an empty comment is refused before it's sent, a too long one on both sides, and one on a note
  that's gone by the handler.
- A server component that fails, inside an `ErrorBox` entrypoint (an error boundary), itself in a
  `Suspense` boundary (so hydrating renders only that part on the client, to show the error), and
  links that `navigate` in place.
- `Today`, an entrypoint showing the date by the clock where it renders: the server's in the HTML,
  then the browser's (a mismatch, if they disagree, that hydration patches).
- Its look is [`weft_ui`](../../packages/weft_ui)'s components (a container, stacks, headings,
  lists, a form whose fields label and describe their inputs, buttons, an alert for the error box,
  chips for related notes), in the notes' colours: [`src/shared/Theme.res`](src/shared/Theme.res)
  sets weft_ui's tokens on the page's outermost element. What's left of the notes' own styles (the
  page's frame, the note's body) is in [`weft_css`](../../packages/weft_css), beside the components.
  Each page is sent the stylesheets of what it renders (the list's in its head, a note's comment
  form's when it's opened); the pages' styles, server-only, reach the client only as CSS.
- A refused comment or title says why on its own field (an empty or too long one), linked to its
  input as its error, or at the form's top (anything else: the note's gone).

Every page is rendered on the server first, and hydrated in the browser.

The "database" ([`src/server/Db.res`](src/server/Db.res)) is in memory, and the queries the page
streams each wait on a gate ([`src/server/Gates.res`](src/server/Gates.res)): in `vp dev`, a timer,
so the streaming is visible by hand; in the tests, closed until the test opens it, so the order
things arrive in is the test's choice.

Run it:

```bash
pnpm --filter @e-cline/weft_notes_example exec vp run dev
```

or build it and serve the build:

```bash
pnpm --filter @e-cline/weft_notes_example exec vp run start
```

## Tests

The elements the tests find have a `data-id` (`dataId` in the JSX), not an `id`, which only those
the page refers to have (the comment's hint, named by its input's `aria-describedby`).

[`tests/Notes_test.res`](tests/Notes_test.res) runs the app's scenarios through the harness: the
server in a worker thread (with the database's controls,
[`tests/FakeDbControl.res`](tests/FakeDbControl.res), called there), each page in jsdom. They cover:

- the first page's shell and first row, then each boundary as its gate opens, in either order, and
  the same page whatever size of chunks the HTML comes in; every first page hydrated over the
  server's nodes (none replaced but the error box's part), with no warnings;
- hydration: the page readable without the bootstrap (and nothing on it working), what was clicked
  and typed before the bootstrap ran done once it has, boundaries swapped in before the bootstrap
  runs and after, the rest of the page hydrated while the like button's chunk loads (and a boundary
  arriving meanwhile), the failing component's error box rendered on the client, and a text the
  client renders differently (`Today`, with the test's clock turned back) patched and warned about;
- the comments' own fallback until their promise resolves, and the failing component's error in its
  box;
- the like button's state across notes and a refresh, links fetching payloads rather than pages, and
  navigating away from a page still streaming, which cancels its response (the database sees its
  queries abandoned) so none of its rows land;
- posting a comment; saving a title, which refetches only the saved title (the same nodes, the
  draft, focus and selection kept, nothing else rendering again);
- the RPCs: an empty title or comment refused with no request made, a comment the handler refuses
  (its note deleted), one the server checks again and refuses (a client that didn't check, played by
  `rewriteBodies`), one the server can't read (an older client's request) shown as such, and liking;
- reloading the comments after another user's changes (new ones inserted, edited ones updated in
  place), while their gate is held (the old ones stay, pending), and twice (the first never lands);
- the server's like count arriving with a refresh while the button keeps its own state;
- the styles: each page's head linking only what it renders, a note's sheets loaded when it's
  navigated to, and nothing shown without its CSS as a note streams in.

[`e2e/notes.e2e.ts`](e2e/notes.e2e.ts) checks, in Chromium against the build, what only a browser
can: the HTML streaming, a chunk loaded once a page needs it and only once, focus and selection
across a refetch, the back button, a comment posted through its RPC (the request as the browser
sends it, `Origin` and all), a boundary's content painted before the bootstrap's chunk has loaded, a
click and typing before then done once it has, and the page readable with JavaScript off; each over
a hydrated page, with nothing in the console. With `WEFT_NOTES_TEST_ROUTES=1`, the server has routes
that open the gates, for these tests. Run them (they need Chromium:
`pnpm --filter @e-cline/weft_notes_example exec playwright install chromium`):

```bash
pnpm --filter @e-cline/weft_notes_example exec vp run e2e
```
