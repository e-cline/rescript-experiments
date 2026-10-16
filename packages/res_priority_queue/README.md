# @e-cline/res_priority_queue

Two priority queues, authored in ReScript: `PriorityQueue` (persistent, a leftist heap) and
`MutablePriorityQueue` (an array-backed binary heap). Both used to be part of
[`@e-cline/res_common`](../res_common) -- as `ImmutablePriorityQueue` and `PriorityQueue`
respectively -- and were split out into their own package, with the immutable one taking the plain
name.

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/res_priority_queue rescript @rescript/runtime
```

Add `"@e-cline/res_priority_queue"` to the `dependencies` in your `rescript.json`. The modules are
under the `ResPriorityQueue` namespace (`ResPriorityQueue.PriorityQueue.make`), and your project's
`rescript build` compiles them along with your own code.

## Layout

- **`MutablePriorityQueue.res`** -- a mutable, array-backed binary heap.
- **`PriorityQueue.res`** -- a persistent leftist heap, following the standard OCaml/Melange
  approach.
- **`tests/TestSupport.res`** (no `_test` suffix, so it isn't itself picked up as a test file) --
  shared test fixtures: an `int` `Belt.Id.comparable` and a seeded Lehmer/Park-Miller PRNG, the
  latter duplicated from `res_common/tests/TestSupport.res` rather than imported from it -- this is
  test-only infrastructure, not something either package's real API should depend on the other for.

The one dependency is `@e-cline/res_common`, for `Debug.fail`: `peekExn`/`dequeueExn` on an empty
queue throw through it, so they fail the same way as every other assertion in these packages.

Like most ReScript libraries, this package has no `exports` map in its `package.json`: it ships its
`.res`/`.resi` source, and the consuming project's compiler builds it, so the compiled files have to
be importable from wherever that project's `rescript.json` puts them.

## Belt usage

Belt has no priority queue or heap of its own (`Belt.MutableStack`/`Belt.MutableQueue` are
unordered) -- confirmed by checking `@rescript/runtime`'s actual module list before writing these,
rather than assuming.

Both queues identify priority via `Belt.Id.comparable` (built with `Belt.Id.MakeComparable`) rather
than a bare `(a, a) => int` function -- the same mechanism `Belt.Set`/`Belt.Map`/`res_trees`'s
`BTree` use, and for the same reason: a compile-time guarantee that two comparator-carrying values
were built from an equivalent comparator, rather than a runtime hope. `make`/`fromArray` both need
the `(type a, id, ...)` locally-abstract-type idiom to unpack the first-class module -- see the root
`RESCRIPT.md`'s gap #11, or `res_trees/README.md`'s "Belt usage" section, for the mechanics.

## The two queues

`MutablePriorityQueue.t` (mutable) is an array-backed binary heap, with the "hole percolation"
`siftUp`/`siftDown` optimization (the moving element is written into the array once, at its final
index, instead of swapped at every level).

`PriorityQueue.t` (persistent) follows the standard purely-functional approach: a **leftist heap**.
Every node tracks its "rank" (the length of its right spine); the leftist invariant is that every
node's left child has rank >= its right child's, which keeps the right spine short (`O(log n)`) and
makes `merge` -- the one operation everything else builds from -- itself `O(log n)`: it walks down
both heaps' short right spines like merging two sorted lists, then swaps children on the way back up
to restore the invariant. `enqueue`/`dequeue` are then just "merge a singleton in" / "merge the
root's two children together." `fromArray` folds `enqueue` over its input (`O(n log n)`) rather than
a pairwise-merge construction (`O(n)`) -- deliberately: `MutablePriorityQueue.fromArray`'s heapify
already covers the case where construction speed matters, and a queue-of-singletons merge loop would
cost real complexity for a structure whose whole point is being simple to read.

## Testing

Every test is written directly in ReScript with
[`rescript-vitest`](https://github.com/cometkim/rescript-vitest), following `res_trees`'s
conventions: ordinary unit tests plus edge cases (empty/single-element queues, duplicate priorities,
custom comparators), and for each queue an oracle-style stress test that cross-checks a long
randomized sequence of enqueues and dequeues against a sorted array rather than hand-computed
expected values.
