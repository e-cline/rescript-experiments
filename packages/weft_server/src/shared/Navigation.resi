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
it (the browser's pushes it onto the history).
*/
let make: (
  Decoder.t,
  ~render: WeftCore.Element.t => unit,
  ~url: string,
  ~onNavigate: string => unit=?,
) => t

/** Renders `element` (the first page's, say) straight away, not in a transition. */
let show: (t, WeftCore.Element.t) => unit

/**
Fetches `url`'s payload and renders it in a transition, then calls `onNavigate`. Resolves once
it's been rendered, or straight away if a newer fetch replaced it; rejects if the payload's root
failed, leaving the screen as it was.
*/
let navigate: (t, string) => promise<unit>

/** `navigate` without `onNavigate` (for going back or forward: the URL has changed already). */
let load: (t, string) => promise<unit>

/** Fetches what's on screen again (`load` of the current URL). */
let refresh: t => promise<unit>

/** The URL of what's on screen. */
let url: t => string

/** The client the page fetches and decodes with. */
let client: t => Decoder.t

/** The page an entrypoint is on. Fails outside one. */
let useNavigation: unit => t

/** An element that can be fetched again, from `useRefetchable`. */
type refetchable = {
  /** What to render: the fetched element, or `children` until there is one (or newer ones come). */
  element: WeftCore.Element.t,
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
let useRefetchable: (~src: string, WeftCore.Element.t) => refetchable
