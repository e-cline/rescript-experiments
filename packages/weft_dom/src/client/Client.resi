/***
Rendering into the page.

```rescript
@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})

switch WeftDom.Dom.document->WeftDom.Dom.body->WeftDom.Dom.querySelector("#app") {
| Value(container) => WeftDom.Client.createRoot(container)->WeftDom.Client.render(<App />)
| _ => ()
}
```

Updates are batched and rendered in a microtask. The exception is an update made in an event handler
(an `on*` prop), which renders before the event returns, as in React, so inputs never lag behind
their state.
*/

/** A tree rendered into a DOM element. */
type root

/** A root rendering into `container`, which it empties first. */
let createRoot: Dom.element => root

/**
A root that hydrates `container`'s content (the server's HTML, from `Html`) with `element`: its
first render adopts the nodes already there instead of creating them, attaching their handlers, in
a transition; after that it's an ordinary root. What an input or checkbox holds is kept, if the user
changed it before hydration. A `Suspense` boundary the server hadn't finished stays as it is until
the page's runtime swaps its content in, then hydrates. Where the HTML and `element` disagree, the
nearest boundary (or the whole root) is rendered on the client instead, with a warning in
development; a text that differs is patched, and attributes that differ are warned about and left.
*/
let hydrateRoot: (Dom.element, WeftCore.Element.t) => root

/** Renders `element` into the root, replacing what it rendered before, in a microtask. */
let render: (root, WeftCore.Element.t) => unit

/** Removes everything the root rendered, at once. */
let unmount: root => unit

/** Calls `f`, then renders every update it made before returning. */
let flushSync: (unit => 'a) => 'a

/**
For tests: calls `f`, then renders every update and runs every effect, repeatedly, until nothing
more is pending. Throws if effects keep scheduling updates for 100 rounds.
*/
let act: (unit => unit) => unit
