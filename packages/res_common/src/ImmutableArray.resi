/***
A persistent (immutable) array: every operation returns a new `ImmutableArray.t`,
never touching the one it was called on.

This is deliberately just "a plain array with a type that guarantees you can't mutate
it by accident", not a tree-backed structure with structural sharing on every edit:
each edit copies the whole array (`O(n)`). If the access pattern calls for cheap
edits of large collections, use `res_trees`'s `BTree`/`MutableBTree` instead.

`t<'a>` is opaque so nothing outside this module can reach in and mutate the array
a `t` wraps -- the one invariant this type exists to hold. `fromArray`/`toArray` copy
for the same reason.

Index-taking functions (`set`, `insertAt`, `removeAt`) do not bounds-check their
index; passing an out-of-range one is a bug in the caller. Use `get` (returns an
`option`) or `getExn` (throws) for bounds-checked reads.
*/

/** An immutable array of `'a`. */
type t<'a>

/** An empty array. */
let make: unit => t<'a>

/** Wraps a copy of `array`, so later mutation of `array` doesn't affect the result. */
let fromArray: array<'a> => t<'a>

/** A fresh mutable copy of the contents, so mutating the result doesn't affect the original. */
let toArray: t<'a> => array<'a>

/** The number of elements. */
let length: t<'a> => int

/** Whether there are no elements. */
let isEmpty: t<'a> => bool

/** The element at `index`, or `None` if `index` is out of bounds. */
let get: (t<'a>, int) => option<'a>

/** The element at `index`. Throws if `index` is out of bounds. */
let getExn: (t<'a>, int) => 'a

/** A copy with the element at `index` replaced by the given value. */
let set: (t<'a>, int, 'a) => t<'a>

/**
A copy with the given value inserted at `index`, shifting later elements right. `index == length`
appends.
*/
let insertAt: (t<'a>, int, 'a) => t<'a>

/** A copy with the element at `index` removed. */
let removeAt: (t<'a>, int) => t<'a>

/** A copy with the given value appended. */
let push: (t<'a>, 'a) => t<'a>

/** A copy without the last element; the empty array itself, unchanged, if it is already empty. */
let pop: t<'a> => t<'a>

/** The first element, or `None` if empty. */
let first: t<'a> => option<'a>

/** The last element, or `None` if empty. */
let last: t<'a> => option<'a>

/**
The elements in `[start, end_)`. `end_` defaults to the length and is clamped to it;
the result is empty if `start >= end_`.
*/
let slice: (t<'a>, ~start: int, ~end_: int=?) => t<'a>

/** A new array holding the first array's elements followed by the second's. */
let concat: (t<'a>, t<'a>) => t<'a>

/** Applies the function to every element, giving a new array of the results. */
let map: (t<'a>, 'a => 'b) => t<'b>

/** The elements for which the predicate returns `true`, in their original order. */
let filter: (t<'a>, 'a => bool) => t<'a>

/** Folds over the elements from first to last, starting from the given accumulator. */
let reduce: (t<'a>, 'b, ('b, 'a) => 'b) => 'b

/** Calls the function on every element, from first to last. */
let forEach: (t<'a>, 'a => unit) => unit

/** Whether the predicate holds for at least one element. `false` when empty. */
let some: (t<'a>, 'a => bool) => bool

/** Whether the predicate holds for every element. `true` when empty. */
let every: (t<'a>, 'a => bool) => bool

/** The first element for which the predicate returns `true`, if any. */
let find: (t<'a>, 'a => bool) => option<'a>

/** The index of the first element for which the predicate returns `true`, if any. */
let findIndex: (t<'a>, 'a => bool) => option<int>

/**
Whether both arrays have the same length and every pair of elements at the same index
is equal according to the given function.
*/
let equal: (t<'a>, t<'a>, ('a, 'a) => bool) => bool
