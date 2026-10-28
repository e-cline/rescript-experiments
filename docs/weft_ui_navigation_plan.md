# Plan: shared navigating links and a refetching error frame

Two things every Weft server-components app writes for itself today: a link that navigates in place,
and an error boundary whose Retry fetches the failed part again. This plan moves them out of the
apps and into shared code, styled by `weft_ui` where they have a look.

## Status

Draft, for review. Nothing is built. The questions are under "Decisions", each with a
recommendation.

## What's there now

- **The same navigating link, four times:**
  - `weft_shop/src/client/Link.res` and `weft_notes/src/client/Link.res` are identical.
  - `weft_split/src/Link.res` is close.
  - The gallery's `NavLink.res` is the same, plus a default class (weft_ui's link look) and a
    `current` prop for `aria-current="page"`.

  Each is an entrypoint (server components render them) whose `onClick` calls
  `WeftServer.Navigation.followLink`.

- **Navigating links inside client code, written by hand:**
  - The shop's cart drawer has an `<a>` that closes the drawer and then calls `followLink`.
  - Its account menu's `Menu.LinkItem` does the same.

  The shop's `Link` can't take an `onFollow` callback, since an entrypoint's props are data.

- **Two error boundaries:**
  - The notes' `ErrorBox` is a `Weft.ErrorBoundary` with a weft_ui `Alert`, and no retry.
  - The shop's `BlockFrame` adds what's hard:
    - `useRefetchable` from the block's own route
    - a Retry that refetches, then resets the boundary only once the refetched block has rendered
      (resetting when `refetch` resolves renders the failed block again)
    - `aria-busy` while refetching
    - an optional interval refresh, for live blocks

  Both have to be entrypoints, because a boundary's fallback is a function.

- **Why weft_ui couldn't hold these:** weft_ui depends on `weft`, `weft_dom` and `weft_css`, not on
  `weft_server`. That's on purpose (v1 plan, Decision 1): a client-only Weft app shouldn't pull in
  the server-components runtime. Both pieces need `WeftServer.Navigation`.
- **`WeftServer.Navigation.url` isn't reactive.** It's a field read, so a link can't re-render by
  itself when the page's URL changes. Today, `aria-current` comes from the server, which renders the
  page (and the link's props) again on each navigation.

## Design

### 1. `WeftServer.Link`: the unstyled primitive, in `weft_server`

The four copies become one entrypoint in `weft_server`:

```rescript
<WeftServer.Link href="/notes/1" className={WeftUi.Link.className()} current=true>
  {text("A note")}
</WeftServer.Link>
```

- **Props:** `href`, `className`, `dataId`, `current` (sets `aria-current="page"`), `ariaLabel`,
  `children`, and `replace` (navigates without a new history entry, for filters, say).
- **A plain click navigates in place;** anything else is left to the browser (`followLink`'s rules:
  modifier keys, `target`, other origins, `#fragment` links).
- **It has no look of its own.** weft_ui's recipes give it one (`Link.className()`,
  `Button.className()`, `Badge.className(~link=true)`), as the gallery's `NavLink` does now.
- **It's in `weft_server`** because it's a framework primitive with no look: every server-components
  app needs it, weft_ui or not (`weft_split` doesn't use weft_ui).

### 2. `weft_ui_server`: the styled pieces that need both

A new small package, `@e-cline/weft_ui_server` (namespace `WeftUiServer`), depending on `weft_ui`
and `weft_server`. Apps on server components add it; client-only apps never see it.

- **`NavLink`**: `WeftServer.Link` in weft_ui's link look by default, with the `tone` and
  `underline` of `WeftUi.Link`. It's the gallery's `NavLink`, made shared. It exists mostly so the
  common case is one component; `WeftServer.Link` with a recipe stays the general form.
- **`RefetchFrame`**: the shop's `BlockFrame`, made shared. It wraps server-rendered `children` in
  an error boundary and `useRefetchable(~src)`:
  - **On failure:** a weft_ui `Alert` (tone danger) saying what failed, with a Retry `Button` that
    is busy while it refetches.
  - **The reset waits for the refetched content to render.** That's the subtle part.
  - **`refreshEvery`** (seconds) refetches on an interval, for live content.
  - **`aria-busy`** while refetching, with weft_ui's dimmed look for content being refetched.
  - **Props:** `src`, `title` (the alert's text, with the error's message after it), `retryLabel`,
    `refreshEvery`, `dataId`.
  - **Without `src`** it's a plain error frame (the notes' `ErrorBox`): the alert and no Retry.
- **`useNavigateLink`**: for links inside client code, such as a menu's or a drawer's. It's a hook
  giving the `onClick` that calls `followLink` and runs an optional `before` (closing the drawer):

  ```rescript
  let follow = WeftUiServer.useNavigateLink()
  <Menu.LinkItem href="/account" onClick={follow(~href="/account")}> ... </Menu.LinkItem>
  ```

  Whether this earns a place over calling `followLink` directly is Decision 4.

### 3. weft_ui itself

- **No dependency changes.** `Menu.LinkItem` and `Breadcrumbs.Item` already take an `onClick` and
  any link as `children`.
- **A `stale` look:** weft_ui gains a recipe for content being refetched (dimmed, with a short
  transition, and none for reduced motion). `RefetchFrame` uses it, as does the shop's `stale`
  class, which it replaces.

### 4. The apps

- **weft_shop:**
  - `Link`, `BlockFrame` and the hand-written `followLink`s become the shared pieces.
  - `BlockFrame`'s `data-id`s (`block-<id>`, `block-error-<id>`, `retry-<id>`), which the tests use,
    are kept by passing `dataId`.
- **weft_notes:** `Link` and `ErrorBox`.
- **weft_split:** `Link` becomes `WeftServer.Link`.
- **The gallery:** `NavLink` becomes `WeftUiServer.NavLink`, and a page shows `RefetchFrame` failing
  and retrying.
- **Every suite stays green.** Behaviour shouldn't change, except where a copy differed from the
  others; any such difference is noted as it's found.

## Phases

| Phase | What                                                                                                                                                                                                                                                                                                                                                               |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 0     | **Spike** (scratchpad only): an entrypoint in `weft_server` itself (the plugin found weft_ui's, but not a package the plugin's own runtime imports); a package depending on both; whether a link could read the URL reactively for `current` (it can't now: is a small `useUrl` in `Navigation` worth adding, or is the server's prop enough?). Correct this plan. |
| 1     | **`WeftServer.Link`**, with tests (harness: plain clicks navigate, modified ones don't, `replace`, `current`), the README and a changeset. weft_split moves onto it.                                                                                                                                                                                               |
| 2     | **`weft_ui_server`**: the package, `NavLink`, `RefetchFrame` (the shop's `BlockFrame` tests carried over to it), weft_ui's `stale` recipe, README and changeset; a gallery page for both.                                                                                                                                                                          |
| 3     | **The apps** on them: the shop, the notes and the gallery. Their suites stay green.                                                                                                                                                                                                                                                                                |

One PR, a commit per framework change, and a check-in with you between phases, as before.

## Decisions

1. **Where the link goes.** Recommendation: **`WeftServer.Link` in weft_server**, unstyled, with the
   styled `NavLink` in weft_ui_server. The alternative is everything in weft_ui_server. That would
   leave apps without weft_ui (weft_split) still writing their own link.
2. **A new package, or a weft_server dependency for weft_ui?** Recommendation: **a new package**
   (`weft_ui_server`). It keeps weft_ui usable without server components, as v1 decided. Adding
   weft_server to weft_ui would be simpler, but every client-only app would carry the
   server-components runtime.
3. **`current`: from the server, or computed?** Recommendation: **from the server for now** (a
   `current` prop, as the gallery does). The server already renders the page again on each
   navigation. A reactive `useUrl` in `Navigation` (and an automatic `current` for a matching
   `href`) is a small addition, but it's a framework change. The spike says whether it's needed.
4. **`useNavigateLink`.** Recommendation: **leave it out.** Calling `followLink` in an `onClick` is
   one line, and the two places that do it are fine as they are. Add it if more turn up.
5. **The notes' `ErrorBox`.** Recommendation: **`RefetchFrame` without `src`,** rather than a second
   component. It's one fewer thing to learn, and a frame without a retry is the same frame.
6. **The name.** Recommendation: `RefetchFrame`. It says what it adds over a plain
   `Weft.ErrorBoundary`. `ErrorFrame` and `BlockFrame` are the alternatives.

## Risks

- **Entrypoints in weft_server.** It has none today. The plugin scans dependencies' files for
  entrypoints, and weft_ui's were found. But weft_server is also what the plugin's own runtime
  imports, so a client chunk for one of its files may need care. Phase 0 checks this first. If it's
  a problem, `Link` moves to weft_ui_server (Decision 1's alternative).
- **`BlockFrame`'s timing.** Its retry logic was hard to get right (see the shop's notes). Moving it
  keeps its tests: they move with it, and the shop's own block tests keep running against the shared
  frame.
- **A small library chunk per entrypoint.** Three more (`Link`, `NavLink` and `RefetchFrame`), built
  into every app that depends on them. That's the same trade-off as v1's ready-made entrypoints.
