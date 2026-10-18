# weft_notes

A small notes app built with [Weft's server components](../../packages/weft_server), and the test
bed for them: every feature, tested the way a browser uses them, through
[`@e-cline/vite_plugin_weft`'s harness](../../packages/vite_plugin_weft#testing-an-app), and a few
things only a browser can show, in Chromium.

- The list of notes, and a note's page ([`src/Pages.res`](src/Pages.res)), with three parts that
  stream in on their own (the body, the comments, related notes), each under a `Suspense` boundary.
- `LikeButton`, an entrypoint with state of its own (whether you just liked it), whose count comes
  from the server.
- `NoteEditor`, a draft of the title in state, the saved title and time as props: saving posts the
  draft, then refetches the header's `Frame`, so new props arrive and the draft, the input, its
  focus and its selection stay.
- The comments in a `Frame` of their own, with a button in it that reloads them (`useFrame`), a
  `CommentList` entrypoint given them as a promise (and showing its own fallback until it resolves),
  and `CommentForm`, which posts a comment and then `refresh`es the page.
- A server component that fails, inside an `ErrorBox` entrypoint (an error boundary), and links that
  `navigate` in place.

The "database" ([`src/Db.res`](src/Db.res)) is in memory, and the queries the page streams each wait
on a gate ([`src/Gates.res`](src/Gates.res)): in `vp dev`, a timer, so the streaming is visible by
hand; in the tests, closed until the test opens it, so the order things arrive in is the test's
choice.

Run it:

```bash
pnpm --filter @e-cline/weft_notes_example exec vp run dev
```

or build it and serve the build:

```bash
pnpm --filter @e-cline/weft_notes_example exec vp run start
```

## Tests

[`tests/Notes_test.res`](tests/Notes_test.res) runs the app's scenarios through the harness: the
server in a worker thread (with the database's controls,
[`tests/FakeDbControl.res`](tests/FakeDbControl.res), called there), each page in jsdom. They cover:

- the first page's shell and first row, then each boundary as its gate opens, in either order, and
  the same page whatever size of chunks the HTML comes in;
- the comments' own fallback until their promise resolves, the failing component's error in its box,
  and the rest of the page rendering while the like button's chunk loads;
- the like button's state across notes and a refresh, links fetching payloads rather than pages, and
  navigating away from a page still streaming, which cancels its response (the database sees its
  queries abandoned) so none of its rows land;
- posting a comment; saving a title, which refetches only the header's frame (the same nodes, the
  draft, focus and selection kept, nothing else rendering again);
- reloading the comments after another user's changes (new ones inserted, edited ones updated in
  place), while their gate is held (the old ones stay, pending), and twice (the first never lands);
- the server's like count arriving with a refresh while the button keeps its own state.

[`e2e/notes.e2e.ts`](e2e/notes.e2e.ts) checks, in Chromium against the build, what only a browser
can: the HTML streaming, a chunk loaded once a page needs it and only once, focus and selection
across a frame's refetch, and the back button. With `WEFT_NOTES_TEST_ROUTES=1`, the server has
routes that open the gates, for these tests. Run them (they need Chromium:
`pnpm --filter @e-cline/weft_notes_example exec playwright install chromium`):

```bash
pnpm --filter @e-cline/weft_notes_example exec vp run e2e
```
