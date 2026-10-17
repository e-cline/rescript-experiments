/***
Rendering into the page.

```rescript
@@jsxConfig({version: 4, module_: "ResFiberDom.Jsx"})

switch ResFiberDom.Dom.document->ResFiberDom.Dom.body->ResFiberDom.Dom.querySelector("#app") {
| Value(container) => ResFiberDom.Client.createRoot(container)->ResFiberDom.Client.render(<App />)
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

/** Renders `element` into the root, replacing what it rendered before, in a microtask. */
let render: (root, ResFiber.Element.t) => unit

/** Removes everything the root rendered, at once. */
let unmount: root => unit

/** Calls `f`, then renders every update it made before returning. */
let flushSync: (unit => 'a) => 'a

/**
For tests: calls `f`, then renders every update and runs every effect, repeatedly, until nothing
more is pending. Throws if effects keep scheduling updates for 100 rounds.
*/
let act: (unit => unit) => unit
