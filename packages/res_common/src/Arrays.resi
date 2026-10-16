/***
Array helpers not already covered by `Belt.Array`/`Belt.SortArray`: immutable
positional splicing, chunking/zipping/partitioning/grouping, and binary search.

Belt has no positional-splice-on-an-immutable-array equivalent, and no
chunk/zip/partition/groupBy/unique/flatten either, so everything here fills one of
those gaps rather than wrapping something Belt already does. The
positional-splice helpers are a public, reusable version of the ones `res_trees`'s internal
`ArrayOps` wrote for its own private use.

None of these functions mutate their input.
*/

/**
Returns a new array with `value` inserted at `index`, shifting everything at or
after `index` one slot to the right. `index` must be in `0..length(array)`;
`index == length(array)` appends.
*/
let insertAt: (array<'a>, int, 'a) => array<'a>

/**
Returns a new array with the element at `index` removed. `index` must be a valid index into `array`.
*/
let removeAt: (array<'a>, int) => array<'a>

/**
Returns a new array with the element at `index` replaced by `value`. `index` must be a valid index
into `array`.
*/
let replaceAt: (array<'a>, int, 'a) => array<'a>

/**
Splits `array` into consecutive chunks of `size` elements each; the final chunk
holds the remainder and may be shorter than `size`. An empty `array` gives `[]`.

`size` must be at least `1`; this is only checked in development builds (via
`Debug.debugAssert`).
*/
let chunk: (array<'a>, int) => array<array<'a>>

/** Pairs up `left` and `right` elementwise, stopping at the shorter array's length. */
let zip: (array<'a>, array<'b>) => array<('a, 'b)>

/** Like `zip`, but combines each pair with the given function instead of tupling it. */
let zipWith: (array<'a>, array<'b>, ('a, 'b) => 'c) => array<'c>

/**
Splits `array` into two arrays: the elements for which the predicate returns
`true`, then everything else, each in their original relative order.
*/
let partition: (array<'a>, 'a => bool) => (array<'a>, array<'a>)

/**
Groups `array`'s elements by the key the given function computes for each one,
preserving each group's original relative order.

The result is a `Belt.Map.String` rather than a hash map, so converting it (e.g. via
`Belt.Map.String.toArray`) yields a deterministic, sorted-by-key order.
*/
let groupBy: (array<'a>, 'a => string) => Belt.Map.String.t<array<'a>>

/**
Returns a new array with duplicate elements removed, keeping only the first
occurrence of each, in original order. The function projects each element to the
key used for equality, so (for example) records can be deduplicated by a field
without the whole record needing to support `Belt.Id.comparable`.
*/
let uniqueBy: (array<'a>, 'a => string) => array<'a>

/**
Flattens one level of nesting.

## Examples

```rescript
Arrays.flatten([[1, 2], [3], [4, 5]]) == [1, 2, 3, 4, 5]
```
*/
let flatten: array<array<'a>> => array<'a>

/**
Returns the leftmost index in `[lo, hi)` at which `value` could be inserted while
keeping `array` sorted according to `~compare`. Equivalent to Python's
`bisect.bisect_left`: if `value` already appears in `array`, the result is the index
of its first (leftmost) occurrence.

`lo` defaults to `0` and `hi` to `Array.length(array)`. `array` must already be
sorted according to `~compare` over `[lo, hi)`; behavior is undefined otherwise.
Runs in `O(log(hi - lo))`.
*/
let bisectLeft: (array<'a>, 'a, ~compare: ('a, 'a) => int, ~lo: int=?, ~hi: int=?) => int

/**
Returns the rightmost index in `[lo, hi)` at which `value` could be inserted while
keeping `array` sorted according to `~compare`. Equivalent to Python's
`bisect.bisect_right`: if `value` already appears in `array`, the result is the
index just past its last (rightmost) occurrence.

`lo` defaults to `0` and `hi` to `Array.length(array)`. `array` must already be
sorted according to `~compare` over `[lo, hi)`; behavior is undefined otherwise.
Runs in `O(log(hi - lo))`.
*/
let bisectRight: (array<'a>, 'a, ~compare: ('a, 'a) => int, ~lo: int=?, ~hi: int=?) => int
