/***
Update priorities, as a bitmask: a fiber's `lanes` are the priorities of its own pending updates,
its `childLanes` those of updates somewhere below it. Only `sync` and `defaultLane` exist so far,
and both render to completion; the bits leave room for transitions and idle work.
*/

type t = int

let none: t = 0
let sync: t = 1
let defaultLane: t = 16

let merge = (a: t, b: t): t => Int.bitwiseOr(a, b)
let intersects = (a: t, b: t): bool => Int.bitwiseAnd(a, b) != 0
let remove = (set: t, lanes: t): t => Int.bitwiseAnd(set, Int.bitwiseNot(lanes))
