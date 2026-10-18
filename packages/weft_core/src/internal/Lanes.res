/***
Update priorities, as a bitmask: a fiber's `lanes` are the priorities of its own pending updates,
its `childLanes` those of updates somewhere below it. A lower bit is a higher priority.

- `sync`: `flushSync` and event handlers. Rendered at once, without yielding.
- `defaultLane`: everything else not in a transition. Rendered in a microtask, without yielding.
- `transition`: updates in `Transition.start`. Rendered in scheduler tasks, yielding to the browser
  between units of work, and thrown away (to start again) when a more urgent update arrives.
- `idle`: lowest priority, rendered like a transition.

A render works on one lane at a time (the highest-priority one pending). Updates in other lanes are
skipped by that render and kept for a later one.
*/

type t = int

let none: t = 0
let sync: t = 1
let defaultLane: t = 16
let transition: t = 256
let idle: t = 1 * 1024 * 1024 * 512

let merge = (a: t, b: t): t => Int.bitwiseOr(a, b)
let intersects = (a: t, b: t): bool => Int.bitwiseAnd(a, b) != 0
let remove = (set: t, lanes: t): t => Int.bitwiseAnd(set, Int.bitwiseNot(lanes))

/** Whether every lane in `subset` is in `set` (true for `none`). */
let isSubset = (set: t, subset: t): bool => Int.bitwiseAnd(subset, Int.bitwiseNot(set)) == none

/** The highest-priority lane in `lanes`: its lowest set bit. */
let highestPriority = (lanes: t): t => Int.bitwiseAnd(lanes, -lanes)

/** Lanes rendered to completion without yielding. */
let isBlocking = (lanes: t): bool => intersects(lanes, merge(sync, defaultLane))
