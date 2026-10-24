/***
The client's page: what's on screen came from a URL, and is replaced by fetching another
(`navigate`), or the same one again (`refresh`), as a payload, and rendering it over the old screen
in a transition. Entrypoints in the same place keep their state, and boundaries already on screen
keep their content until what replaces it is ready. Fetches replace each other: a response that
arrives after a newer one is dropped, and its stream cancelled.

`Bootstrap` makes the browser's; a test can make one over any renderer. Entrypoints reach it with
`useNavigation`:

```rescript
// in an entrypoint
let navigation = WeftServer.Navigation.useNavigation()
<button onClick={_ => navigation->WeftServer.Navigation.refresh->ignore}> {...} </button>
```

An entrypoint can fetch part of the page again by itself with `useRefetchable`: given `children`
from the server, it shows them until it's refetched, then what it fetched.

```rescript
// in an entrypoint, given the comments (rendered on the server) as `children`
let comments = WeftServer.Navigation.useRefetchable(~src=`/notes/${noteId}/comments`, children)
<section>
  <button onClick={_ => comments.refetch()->ignore}> {...} </button> // comments.isPending
  comments.element
</section>
```
*/

type t

/**
A page, fetching with `client` and showing elements with `render` (a root's `render`). `url` is
the URL of what's on screen; `onNavigate` is called with the new one when `navigate` has rendered
it (the browser's pushes it onto the history). If the server redirected the fetch, the new URL is
where it was redirected to (as `client`'s `fetch` reports it), not the one asked for; a `load` or
`refresh` that was redirected calls `onRedirect` with it instead (the browser's replaces the
current history entry with it).

`onFailed` is what happens instead when `navigate` or `load` can't show a URL (its payload couldn't
be fetched, or its root failed): the browser's loads the page the ordinary way, adding it to the
history when `push` is true (a `navigate`), and in place of the current entry otherwise (a `load`,
for going back or forward). Without it, they reject.
*/
let make: (
  Decoder.t,
  ~render: Weft.Element.t => unit,
  ~url: string,
  ~onNavigate: string => unit=?,
  ~onRedirect: string => unit=?,
  ~onFailed: (string, ~push: bool) => unit=?,
) => t

/**
The page an HTML render on the server reads (`Page` makes one): `url` is the request's, `client` the
server's own decoder. Entrypoints that call `useNavigation` (or `useRefetchable`, or `Rpc.use`) while
they render get it; asking it to fetch (`navigate`, `refresh`, a refetch) fails, since those are for
handlers and effects, which only run in the browser.
*/
let makeForServer: (Decoder.t, ~url: string) => t

/**
`element` inside the page's context, as `show` renders it: what to hydrate with, so the first render
matches what the server rendered.
*/
let wrap: (t, Weft.Element.t) => Weft.Element.t

/** Renders `element` (the first page's, say) straight away, not in a transition. */
let show: (t, Weft.Element.t) => unit

/**
Fetches `url`'s payload, starts rendering it in a transition, and calls `onNavigate` (with where
a redirect led, if the server redirected it). Resolves once
the new page is on screen (the transition has committed: a page still waiting on what it needs
before it can show takes as long as that takes), or as soon as a newer fetch or page replaces it.
If the payload can't be fetched or its root failed, the screen is left as it was, and `onFailed` is
called (or, without it, the promise rejects).
*/
let navigate: (t, string) => promise<unit>

/**
`navigate` without `onNavigate` (for going back or forward: the URL has changed already), calling
`onRedirect` instead if the server redirected it.
*/
let load: (t, string) => promise<unit>

/**
Fetches what's on screen again, and resolves once it's rendered, as `navigate` does. If that fails,
it rejects, even with `onFailed`: the page's state (what's been typed, say) stays, rather than being
thrown away by a page load.
*/
let refresh: t => promise<unit>

/**
Whether a click on a link to `href` (relative to `from`, the current URL) should be followed in
place, by `navigate`, rather than left to the browser: only a plain click (the main button, no
modifier keys, so not one opening a new tab or window) not already handled (`preventDefault`), on
a link to this origin without a `target` or `download`, and not one to a part of the page `from`
is (`#comments`), which the browser scrolls to.
*/
let staysInPage: (WeftDom.Dom.event, ~href: string, ~from: string) => bool

/**
What a link's `onClick` does: `navigate`s to `href` in place of the browser's following it, if
`staysInPage` (from the current URL) says so, and otherwise leaves the click to the browser.

```rescript
// in an entrypoint
let navigation = WeftServer.Navigation.useNavigation()
<a href onClick={event => navigation->WeftServer.Navigation.followLink(event, ~href)->ignore}>
  children
</a>
```
*/
let followLink: (t, WeftDom.Dom.event, ~href: string) => promise<unit>

/** The URL of what's on screen (where a redirect led, if the server redirected its fetch). */
let url: t => string

/** The client the page fetches and decodes with. */
let client: t => Decoder.t

/** The page an entrypoint is on. Fails outside one. */
let useNavigation: unit => t

/** An element that can be fetched again, from `useRefetchable`. */
type refetchable = {
  /** What to render: the fetched element, or `children` until there is one (or newer ones come). */
  element: Weft.Element.t,
  /** Fetches `src` again (or `url`) and shows what it gets, in a transition. */
  refetch: (~url: string=?) => promise<unit>,
  /** True from a refetch's start until what it fetched has rendered. */
  isPending: bool,
}

/**
`children` (rendered on the server), until `refetch` fetches `src` (or a URL it's given) as a payload
and replaces them with that. What the hard parts of doing this by hand are, done:

- **Newer wins.** If newer `children` come (a `navigate` or `refresh` rendered this place again with
  new ones from the server), they're shown instead of what was refetched, and a refetch after that
  wins over them in turn. (`useState(() => children)` would keep showing what it first got.)
- **Fetches replace each other.** A refetch cancels the one before it, whose result is dropped, so a
  slow response can't land after a newer one.
- **In a transition.** What's on screen stays (no fallbacks) until what replaces it is ready, and
  `isPending` covers the fetch as well as the render.

Render `element` where the children would go. The promise `refetch` returns resolves once the
render has been started, or straight away if a newer refetch replaced it, and rejects (leaving the
screen as it was) if the payload's root failed.
*/
let useRefetchable: (~src: string, Weft.Element.t) => refetchable
