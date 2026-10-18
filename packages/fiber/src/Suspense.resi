/***
Shows a fallback while the components below it wait for data.

```rescript
let user = fetchUser(id) // a promise, made once (outside the component, or cached)

module Profile = {
  @jsx.component
  let make = () => {
    let user = Fiber.Hooks.use(user)
    <h1> {Jsx.string(user.name)} </h1>
  }
}

<Fiber.Suspense fallback={<Spinner />}> <Profile /> </Fiber.Suspense>
```

`Hooks.use(promise)` returns what the promise resolved to. Before it settles, it suspends: rendering
stops at the nearest `Suspense` boundary, which shows `fallback` instead of its children, and renders
the children again once the promise settles. A rejected promise throws its error, for an
`ErrorBoundary` to catch.

Pass the same promise on every render: the render that suspends is thrown away, so a promise made
while rendering would be a new one each time, and never finish. A promise suspends the first time
it's used even if it has already resolved, since its result can only be read asynchronously; after
that, `use` returns the result straight away.

Children that suspend after they've been shown aren't unmounted: they stay mounted, hidden (the
host's `hideInstance`: `display: none` in the DOM), with their state, until they can render again.
Their effects stay as they were meanwhile, and updates to them wait until they're shown. (Unlike
React, which disconnects hidden children's layout effects and refs, and hides portal content too.)
In a transition (`Transition.start`, `useTransition`), a boundary that's showing its children
doesn't switch to its fallback: the transition's render is abandoned and the screen keeps its
previous state (`useTransition`'s `isPending` stays `true`) until the promise settles, when the
transition renders again, or another update arrives. Urgent updates, and boundaries that appear in
the transition, show the fallback as usual. A transition that suspends with no boundary above waits
the same way, instead of failing.
*/

type props = {fallback: Element.t, children: Element.t}

let make: JsxCore.component<props>
