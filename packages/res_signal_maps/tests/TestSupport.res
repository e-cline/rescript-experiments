/***
Shared support for the test files in this package. Not itself a test (no `_test` suffix, so Vitest's
`test.include` never picks it up).
*/

open ResBTree

/**
Comparators for plain `int`/`string` keys -- duplicated from
`res_b_tree/tests/TestSupport.res` rather than imported from it, matching
that package's own convention: this is test-only infrastructure, not
something either package's real API should depend on the other for.
*/
module IntCmp = Belt.Id.MakeComparable({
  type t = int
  let cmp = (a: int, b: int) => a - b
})

let intId: Belt.Id.comparable<int, IntCmp.identity> = module(IntCmp)

module StringCmp = Belt.Id.MakeComparable({
  type t = string
  let cmp = (a: string, b: string) =>
    if a < b {
      -1
    } else if a > b {
      1
    } else {
      0
    }
})

let stringId: Belt.Id.comparable<string, StringCmp.identity> = module(StringCmp)

/** Builds an `int`-keyed `BTree.t` from an array of pairs, for tests that need one directly. */
let intTree = (entries: array<(int, 'v)>): BTree.t<int, 'v, IntCmp.identity> =>
  BTree.fromArray(~id=intId, entries)
