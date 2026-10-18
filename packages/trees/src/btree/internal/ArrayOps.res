/***
The array operations `BTree`'s nodes are built with. Every one returns a new array that is
*packed* and *exactly sized*, which is what V8 needs to keep reading it quickly:

- An array made with `new Array(n)` and then filled is `HOLEY` for the rest of its life, and so is
  every array later sliced from it: each read then has to check for a hole.
- An array grown with `push` carries spare capacity (about half its length again, plus 16 slots),
  which in a tree of small nodes can be most of the memory.

So everything here is a single call to `slice`, `toSpliced` or `concat` (all three size their
result exactly, and give a packed result for packed input), followed where needed by writes to
indices that already exist. Measured on Node 24, `slice` then one write is quicker than `with`,
and `toSpliced` is the quickest way to insert (about 1.5-2x the cost of a plain `slice`; there is
no way to make a longer array out of `slice`).

None of these functions modifies its argument or checks its indices.
*/

/** A copy of the whole array. */
@send
external copy: array<'a> => array<'a> = "slice"

/** The elements at `[from, to_)`. */
@send
external slice: (array<'a>, int, int) => array<'a> = "slice"

/** The elements from `from` to the end. */
@send
external sliceFrom: (array<'a>, int) => array<'a> = "slice"

/** With `value` inserted before the element at `index` (or at the end, if `index` is the length). */
@send
external insertAt: (array<'a>, int, @as(0) _, 'a) => array<'a> = "toSpliced"

/** Without the element at `index`. */
@send
external removeAt: (array<'a>, int, @as(1) _) => array<'a> = "toSpliced"

/** With two elements inserted before the element at `index`. */
@send
external insertTwoAt: (array<'a>, int, @as(0) _, 'a, 'a) => array<'a> = "toSpliced"

/** With the two elements from `index` replaced by four. */
@send
external replaceTwoWithFour: (array<'a>, int, @as(2) _, 'a, 'a, 'a, 'a) => array<'a> = "toSpliced"

/** With the four elements from `index` replaced by two. */
@send
external replaceFourWithTwo: (array<'a>, int, @as(4) _, 'a, 'a) => array<'a> = "toSpliced"

/** `left` followed by `right`. */
@send
external concat: (array<'a>, array<'a>) => array<'a> = "concat"

/** `left`, then `middle`, then `right`. */
@send
external concat3: (array<'a>, array<'a>, array<'a>) => array<'a> = "concat"

/** With the element at `index` replaced by `value`. */
let replaceAt = (array: array<'a>, index: int, value: 'a): array<'a> => {
  let result = copy(array)
  Array.setUnsafe(result, index, value)
  result
}
