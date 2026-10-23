/***
Updates that can wait.

```rescript
Weft.Transition.start(() => setQuery(_ => text))
```

Updates made inside `start` are transitions: they render in scheduler tasks that yield to the browser
between units of work, and a more urgent update (typing, a click) interrupts them; the transition
then starts again from what's on screen. Meanwhile the screen keeps showing the previous state, so
nothing flickers into a half-updated view. See also `Hooks.useTransition` (which says whether one is
pending) and `Hooks.useDeferredValue`.
*/

/** Calls `f`, making every update in it a transition. */
let start: (unit => unit) => unit
