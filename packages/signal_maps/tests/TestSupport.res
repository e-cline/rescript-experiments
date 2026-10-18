/***
Shared support for the test files in this package. Not itself a test (no `_test` suffix, so Vitest's
`test.include` never picks it up).
*/

open Trees

/**
Comparators for plain `int`/`string` keys -- duplicated from
`trees/tests/TestSupport.res` rather than imported from it, matching
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

/**
The package's own `AtomMap`/`ComputedMap` as a `SignalMap.Maps`, with a `fromArray` that doesn't take
a node size, as the other trees' have.
*/
module BTreeMaps = {
  type tree<'k, 'v, 'id> = BTree.t<'k, 'v, 'id>
  module ComputedMap = ComputedMap
  module AtomMap = {
    include AtomMap
    let fromArray = (~name=?, ~historyLength=?, ~id, entries) =>
      AtomMap.fromArray(~name?, ~historyLength?, ~id, entries)
  }
}

module AvlTreeMaps = SignalMap.Make(AvlTree)

module ChunkTreeMaps = SignalMap.Make(ChunkTree)
