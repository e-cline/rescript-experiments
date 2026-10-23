/***
A renderer that keeps its nodes in memory, for testing components and the reconciler without a DOM.
Concurrent work (transitions) runs on `TestScheduler`, so it only happens inside `act` or when a test
calls `TestScheduler.flushTask`/`flushAll`.

Write the components with `@@jsxConfig({version: 4, module_: "WeftCore.TestJsx"})`. Each renderer
(`create`) records every host operation it performs, so a test can check not just what's rendered
but that the reconciler did no more than it had to:

- `create div#a` / `create "text"`: a new node (`#a` is its `id` prop).
- `append li#c to ul#list` / `insert li#c before li#a` / `remove li#b`: an attached node moved,
  inserted or removed. `root` is the container. Building a new subtree before it's attached isn't
  logged; attaching it is.
- `update div#a {className, title}`: props shown in `toString` changed (handler changes aren't
  logged).
- `text "old" -> "new"`: a text node changed.
- `hide span#a` / `unhide span#a`: a node hidden behind (or shown again from behind) a `Suspense`
  fallback. `toString` leaves hidden nodes out.
*/

/** A rendered node: a host element, or text (whose `tag` is `"#text"`). A `ref` receives one. */
type instance = TestJsx.node

/** A test renderer with one root. */
type t

let create: unit => t

/** Renders `element`, replacing what was rendered before, and returns once it's on screen. */
let render: (t, Element.t) => unit

/** Removes everything rendered. */
let unmount: t => unit

/**
Schedules a render of `element`, as a real renderer's `render` does: it happens in a microtask, or
in an enclosing `flushSync`. For tests about timing; `render` is the usual way.
*/
let scheduleRender: (t, Element.t) => unit

/**
Calls `f`, then renders what it scheduled: the host is updated and layout effects have run when it
returns, but `useEffect`s haven't (they run in a `setTimeout`, or in the next `act`).
*/
let flushSync: (unit => 'a) => 'a

/**
Calls `f`, then renders every update it made (transitions too, without yielding) and runs every
effect, repeatedly, until nothing more is pending: wrap updates in this. Throws if effects keep scheduling updates for 100 rounds.
*/
let act: (unit => unit) => unit

/**
What's rendered, as markup: `<ul id="list"><li>a</li></ul>`. Attributes are the props of
`TestJsx.Elements.props` other than handlers and `children`, sorted by name.
*/
let toString: t => string

/** The host operations performed since `create` or the last `clearOps`. */
let ops: t => array<string>

let clearOps: t => unit

/**
A separate container for `portal`s to render into, named `name` in the operation log (the root's
container is `root`).
*/
type target

let createTarget: (t, string) => target

/** `children`, rendered into `target`: see `Portal`. */
let portal: (target, Element.t) => Element.t

/** What's rendered into `target`, as `toString` writes it. */
let targetToString: target => string

/** The first host element, in document order, whose `id` prop is `id` (the root, then targets). */
let findById: (t, string) => option<instance>

/** Calls the `onClick` of the element with `id`, inside `act`. Throws if there isn't one. */
let click: (t, string) => unit

/** Calls the `onInput` of the element with `id` with `value`, inside `act`. Throws if there isn't one. */
let input: (t, string, string) => unit

/** A number unique to `instance` within its renderer: equal numbers mean the same node. */
let uid: instance => int

let tag: instance => string
let props: instance => TestJsx.Elements.props
let text: instance => string
let children: instance => array<instance>

// Hydrating

/**
A renderer whose root hydrates `markup` (in `toString`'s format, with `<!--$-->`, `<!--$?-->`,
`<!--$!-->` and `<!--/$-->` comments for boundaries' markers, and `<!-- -->` between texts) with
`element`, as `hydrateRoot` would over a server's HTML; returns once it's done. Hydration's own
operations are logged too: `hydrate div#a` (a node claimed), `remove ...` (one nothing claimed),
`clear a boundary's server content`, `clear root`.
*/
let hydrate: (string, Element.t) => t

/** What's rendered, comments (markers) included: the parsed content, as hydration left it. */
let toMarkup: t => string

/**
The first pending boundary's content arriving from the server, as `markup`: it replaces the
fallback, the marker says complete, and hydration is told (as the page's runtime would).
*/
let resolveBoundary: (t, string) => unit

/** The first pending boundary failing on the server: the marker says so, and hydration is told. */
let failBoundary: t => unit
