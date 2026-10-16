# ChunkTree

A persistent sorted map built on a leaf-chunked AVL tree: the [AVL tree](../avl/README.md)'s
height-balanced binary spine, with small sorted arrays as leaves instead of single entries. It has
`AvlTree`'s interface, keeps its fast point writes and its cheap `diff`, and iterates and reads by
position about twice as fast. `MutableChunkTree` is the same mutable wrapper the other two trees
have.

Both live in `res_trees` alongside the other trees, under the same namespace: `ResTrees.ChunkTree`
and `ResTrees.MutableChunkTree`.

```rescript
module IntCmp = Belt.Id.MakeComparable({
  type t = int
  let cmp = (a: int, b: int) => a - b
})

let before = ResTrees.ChunkTree.fromArray(~id=module(IntCmp), [(1, "one"), (2, "two"), (3, "three")])
let after = before->ResTrees.ChunkTree.set(2, "TWO")->ResTrees.ChunkTree.remove(3)

ResTrees.ChunkTree.getAt(after, 1) // Some((2, "TWO"))

ResTrees.ChunkTree.diff(
  before,
  after,
  ~onlyLeft=(key, _) => Console.log2("removed", key), // removed 3
  ~different=(key, _, _) => Console.log2("changed", key), // changed 2
)
```

Leaves hold up to 16 entries. `ChunkTree.Make({let maxLeafSize = 32})` gives the same tree with
another maximum (at least 2). The API is `AvlTree`'s, `SortedMap.S`, documented in
[`SortedMap.res`](../SortedMap.res).

## How it measures

Both leaf sizes against `AvlTree`, at 1,000, 10,000 and 100,000 random `int` keys, each benchmark
run alone in several processes (see [`benchmarks/`](../../benchmarks)); a multiple below 1.00 is
faster than `AvlTree`. Regenerate it with `vp run bench:readme` there, after `vp run bench:record`.

<!-- res-bench filter="^(ChunkTree|ChunkTree32|AvlTree)\." relative="AvlTree" -->

|                                                |             AvlTree |           ChunkTree |         ChunkTree32 |
| ---------------------------------------------- | ------------------: | ------------------: | ------------------: |
| get n=1000                                     |  19.97 µs\* (1.00x) |  18.94 µs\* (0.95x) |  18.93 µs\* (0.95x) |
| get n=10000                                    |  44.79 µs\* (1.00x) |    48.12 µs (1.07x) |  43.86 µs\* (0.98x) |
| get n=100000                                   |    84.99 µs (1.00x) |  83.99 µs\* (0.99x) |  78.69 µs\* (0.93x) |
| set (build) n=1000                             |   119.48 µs (1.00x) | 146.34 µs\* (1.22x) | 143.93 µs\* (1.20x) |
| set (build) n=10000                            |     2.12 ms (1.00x) |     2.41 ms (1.13x) |     2.30 ms (1.08x) |
| set (build) n=100000                           |  42.47 ms\* (1.00x) |    39.68 ms (0.93x) |    34.64 ms (0.82x) |
| set (overwrite) n=1000                         |   104.33 µs (1.00x) |   102.81 µs (0.99x) |  96.33 µs\* (0.92x) |
| set (overwrite) n=10000                        |   163.58 µs (1.00x) |   161.81 µs (0.99x) |   149.53 µs (0.91x) |
| set (overwrite) n=100000                       |   242.34 µs (1.00x) | 295.33 µs\* (1.22x) |   217.46 µs (0.90x) |
| set (insert) n=1000                            | 142.91 µs\* (1.00x) | 178.30 µs\* (1.25x) |   176.24 µs (1.23x) |
| set (insert) n=10000                           |   179.82 µs (1.00x) | 212.13 µs\* (1.18x) |   207.30 µs (1.15x) |
| set (insert) n=100000                          |   217.94 µs (1.00x) |   232.00 µs (1.06x) |   237.54 µs (1.09x) |
| remove n=1000                                  |  97.84 µs\* (1.00x) |   174.56 µs (1.78x) | 148.72 µs\* (1.52x) |
| remove n=10000                                 |   181.60 µs (1.00x) |   239.02 µs (1.32x) | 226.19 µs\* (1.25x) |
| remove n=100000                                | 253.58 µs\* (1.00x) | 302.04 µs\* (1.19x) |   287.54 µs (1.13x) |
| forEach n=1000                                 |   8.33 µs\* (1.00x) |     8.29 µs (0.99x) |     8.30 µs (1.00x) |
| forEach n=10000                                |    87.67 µs (1.00x) |    83.09 µs (0.95x) |    83.24 µs (0.95x) |
| forEach n=100000                               |   979.82 µs (1.00x) | 835.07 µs\* (0.85x) |   830.90 µs (0.85x) |
| reduce n=1000                                  |     2.80 µs (1.00x) |   929.52 ns (0.33x) |   690.93 ns (0.25x) |
| reduce n=10000                                 |    65.16 µs (1.00x) |    13.25 µs (0.20x) |     9.37 µs (0.14x) |
| reduce n=100000                                | 932.61 µs\* (1.00x) | 606.99 µs\* (0.65x) |   583.62 µs (0.63x) |
| toArray n=1000                                 |     6.13 µs (1.00x) |     3.75 µs (0.61x) |     3.45 µs (0.56x) |
| toArray n=10000                                |  80.73 µs\* (1.00x) |    47.81 µs (0.59x) |    40.37 µs (0.50x) |
| toArray n=100000                               |   1.54 ms\* (1.00x) |   824.00 µs (0.53x) |   718.37 µs (0.47x) |
| keysArray n=1000                               |   3.82 µs\* (1.00x) |     1.51 µs (0.39x) |     1.25 µs (0.33x) |
| keysArray n=10000                              |  64.56 µs\* (1.00x) |    18.23 µs (0.28x) |    13.91 µs (0.22x) |
| keysArray n=100000                             |   975.63 µs (1.00x) |   322.99 µs (0.33x) |   232.69 µs (0.24x) |
| getAt n=1000                                   |  28.36 µs\* (1.00x) |    13.26 µs (0.47x) |  11.59 µs\* (0.41x) |
| getAt n=10000                                  |    60.59 µs (1.00x) |  31.33 µs\* (0.52x) |  22.61 µs\* (0.37x) |
| getAt n=100000                                 |   101.42 µs (1.00x) |  60.68 µs\* (0.60x) |    57.36 µs (0.57x) |
| indexOf n=1000                                 |  25.69 µs\* (1.00x) |  20.39 µs\* (0.79x) |  17.46 µs\* (0.68x) |
| indexOf n=10000                                |    55.05 µs (1.00x) |  40.59 µs\* (0.74x) |    34.94 µs (0.63x) |
| indexOf n=100000                               |    92.59 µs (1.00x) |  80.55 µs\* (0.87x) |    66.03 µs (0.71x) |
| diff (10 overwrites) n=1000                    |   416.49 ns (1.00x) |   381.83 ns (0.92x) |   431.85 ns (1.04x) |
| diff (10 overwrites) n=10000                   |   728.45 ns (1.00x) |   726.68 ns (1.00x) |   697.79 ns (0.96x) |
| diff (10 overwrites) n=100000                  |   997.06 ns (1.00x) |   904.59 ns (0.91x) |     1.04 µs (1.05x) |
| diff (30 mixed edits) n=1000                   |     1.67 µs (1.00x) |     1.26 µs (0.75x) |     1.63 µs (0.97x) |
| diff (30 mixed edits) n=10000                  |     2.00 µs (1.00x) |     1.41 µs (0.71x) |     2.04 µs (1.02x) |
| diff (30 mixed edits) n=100000                 |   2.80 µs\* (1.00x) |     2.01 µs (0.72x) |     2.22 µs (0.79x) |
| diff (equal, rebuilt the same way) n=1000      |     7.19 µs (1.00x) |     3.48 µs (0.48x) |     2.77 µs (0.39x) |
| diff (equal, rebuilt the same way) n=10000     |   113.39 µs (1.00x) |    43.63 µs (0.38x) |    32.41 µs (0.29x) |
| diff (equal, rebuilt the same way) n=100000    |   1.42 ms\* (1.00x) |   522.93 µs (0.37x) |   348.76 µs (0.25x) |
| diff (equal, built from sorted input) n=1000   |    26.44 µs (1.00x) |     3.16 µs (0.12x) |     2.58 µs (0.10x) |
| diff (equal, built from sorted input) n=10000  |   290.85 µs (1.00x) |    41.24 µs (0.14x) |    29.42 µs (0.10x) |
| diff (equal, built from sorted input) n=100000 |     3.21 ms (1.00x) |   526.92 µs (0.16x) |   380.33 µs (0.12x) |

Median time per call. In brackets, each time's multiple of AvlTree's. \* marks a benchmark whose
processes landed more than 10% apart. Measured with each benchmark in 5 processes of its own, with
Node v24.22.0 on Apple M2 Pro, 2026-10-16.

<!-- /res-bench -->

So against the AVL tree: positional access and building arrays are faster across the board (`getAt`
1.7-2.1x, `toArray` and `keysArray` 1.6-3.5x), and `reduce` 1.5-5x, while `get` and `forEach` are
about level. Diffs are level or faster: 1.0-1.4x on trees a few edits apart, 2-8x on equal trees
sharing nothing. Inserting and removing keys are the cost, at 1.1x to 1.8x slower (worst on small
trees, where a larger share of edits split or repair a leaf). Larger leaves give up some of the
advantage on diffs of a few edits for faster reads; in these measurements they were as good or
better at point writes too. 16 stays the default because diffs a few edits apart are what this
package cares most about.

These are cheap `int` keys in random order. Two things that would plausibly change the picture
haven't been measured: keys that are expensive to compare (a leaf is searched by binary search, so
the number of comparisons per lookup is about the same as the AVL tree's, but this hasn't been
checked), and ascending insertion, which leaves leaves half full because a full leaf splits evenly.

## How it works

### The node

[`internal/ChunkNode.res`](internal/ChunkNode.res) has the full description. In short:

- **One record for both kinds of node**, `{key, size, height, left, right, keys, values}`, so every
  property read in a descent sees one object shape. A leaf has `height == 1` and its entries in
  `keys` and `values`, two parallel sorted arrays; an internal node has a separator `key`, two
  non-empty children, and one shared empty array in `keys`/`values`.
- **Entries live only in leaves.** A separator divides its children (everything left is below it,
  everything right at or above it) and need not be a key the tree still holds.
- **The spine is balanced exactly as `AvlNode`'s is**, including the AVL tree's fast path: where an
  edit didn't change a subtree's height, nothing above it is rebalanced.
- **Leaves hold between `max / 2` and `max` entries** (the root may hold fewer). A full leaf splits
  evenly under a new internal node. A leaf taken below the minimum is repaired using the
  neighbouring leaf across its parent's separator: the two merge if together they hold fewer than
  `max`, and otherwise share their entries out evenly.
- **Leaf arrays are built at their exact length from packed arrays** (`slice`, `concat`,
  `toSpliced`), so V8 keeps them packed, with no spare capacity.

`size` on every node is what makes `getAt` and `indexOf` `O(log n)`, as in the AVL tree, and the
diff uses it too.

### Diffing

[`internal/ChunkDiff.res`](internal/ChunkDiff.res) works the way the AVL tree's diff does: a subtree
that is the same object on both sides is skipped whole, and a pair of subtrees is compared in one of
two ways.

- **In step**, while two internal nodes have the same separator: their left subtrees cover the same
  keys, as do their right subtrees, so each pair is compared by plain recursion.
- **With cursors**, for anything else: an in-order cursor over each side, merging two leaves as two
  sorted runs, and otherwise opening the larger of two pending subtrees (by `size`) first.

What leaves add: an overwrite copies a leaf's `values` but keeps its `keys` array, so two leaves
with the same `keys` array are known to hold the same keys. Their values are compared pairwise with
no call to the comparator at all. And two values that are the same object are taken as equal without
calling `valueEqual`, as the values inside a skipped subtree already are.

### The parts

- [`ChunkTree.res`](ChunkTree.res) / [`ChunkTree.resi`](ChunkTree.resi): the public module, the
  `Make` functor that fixes the leaf size, and the default instance.
- [`MutableChunkTree.res`](MutableChunkTree.res): one mutable cell holding the latest `ChunkTree.t`,
  as `MutableAvlTree` and `MutableBTree` are.
- [`internal/ChunkMap.res`](internal/ChunkMap.res): every operation at any leaf size, as functions
  of a root and a comparator.
- [`internal/ChunkNode.res`](internal/ChunkNode.res) and
  [`internal/ChunkDiff.res`](internal/ChunkDiff.res): the node and the diff.

## Where it came from

The design came out of a survey of alternatives to the AVL tree, looking for a structure that closed
its two gaps against a B-tree (iteration over large trees, and `getAt`) without giving up its diff.
Leaf-chunked binary trees appear in the literature as PaC-trees and C-trees, where they match or
beat one-entry-per-node trees at about a quarter of the memory; this one was written for this
package and measured against the AVL tree and a redesigned B+tree through a shared harness (see
below). Memory use hasn't been measured here.

Known rough edges, from that first version:

- **Removal** is the slowest operation relative to the AVL tree. Repairing an underfull leaf builds
  the underfull leaf first and then rebuilds it, and sharing entries with a neighbour allocates six
  arrays; both look avoidable.
- **Inserting** copies the leaf's two arrays with `toSpliced`, each about twice the cost of a plain
  copy.
- **A merged leaf** has room for only one more entry before it splits again.

## Testing

In [`tests/chunk/`](../../tests/chunk):

- `ChunkTree_test.res` runs the shared conformance suite
  ([`tests/candidates/Conformance.res`](../../tests/candidates/Conformance.res): every operation
  cross-checked against `Belt.Map.Int`, `checkInvariants` after every edit, and diffs against a
  plain comparison) at leaf sizes 2, 5, 8, 16 and 32. It then tests what the suite can't see from
  outside: where leaves split, merge and borrow, that an overwrite shares the leaf's `keys`, how
  many comparator calls a diff makes, and that `checkInvariants` rejects broken trees.
- `MutableChunkTree_test.res` covers the mutable wrapper.

## Benchmarks

From [`benchmarks/`](../../benchmarks), `ChunkTree` at its default leaves of 16, and at leaves of
32, alongside `AvlTree`:

```bash
vp run bench "^(ChunkTree|ChunkTree32|AvlTree)\."
```

Every operation is measured on each, and the run ends with a table of them side by side; see
[`benchmarks/src/SortedMapSuite.res`](../../benchmarks/src/SortedMapSuite.res) for what is measured,
and that directory's README for more reliable numbers.
