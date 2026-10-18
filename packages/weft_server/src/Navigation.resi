/***
The client's page: what's on screen came from a URL, and is replaced by fetching another
(`navigate`), or the same one again (`refresh`), as a payload, and rendering it over the old screen
in a transition. Entrypoints in the same place keep their state, and boundaries already on screen
keep their content until what replaces it is ready. Fetches replace each other: a response that
arrives after a newer one is dropped, and its stream cancelled.

`Bootstrap` makes the browser's; a test can make one over any renderer. Entrypoints reach it with
`useNavigation`, and parts of the page (`Frame`s) with `useFrame`:

```rescript
// in an entrypoint
let navigation = WeftServer.Navigation.useNavigation()
<button onClick={_ => navigation->WeftServer.Navigation.refresh->ignore}> {...} </button>

let comments = WeftServer.Navigation.useFrame("comments")
<button onClick={_ => comments.refetch()->ignore}> {...} </button> // comments.isPending
```
*/

type t

/**
A page, fetching with `client` and showing elements with `render` (a root's `render`). `url` is
the URL of what's on screen; `onNavigate` is called with the new one when `navigate` has rendered
it (the browser's pushes it onto the history).
*/
let make: (
  Client.t,
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
let client: t => Client.t

/** The page an entrypoint is on. Fails outside one. */
let useNavigation: unit => t

/** A part of the page that can be fetched again on its own (see `Frame`). */
type frame = {
  /** Fetches the frame's `src` again (or `url`), and renders it in the frame's place. */
  refetch: (~url: string=?) => promise<unit>,
  /** True from a refetch's start until what it fetched has rendered. */
  isPending: bool,
}

/**
The frame named `name` on the page, from anywhere on it. Until a frame with that name has mounted,
`refetch` does nothing and `isPending` is false.
*/
let useFrame: string => frame

/** The frame named `name` on the page as it is now, outside a component (for tests, say). */
let frame: (t, string) => frame

/** For `Frame`: registers the frame `name`'s refetch and pending state. */
let registerFrame: (
  t,
  string,
  ~refetch: (~url: string=?) => promise<unit>,
  ~isPending: bool,
) => unit => unit
