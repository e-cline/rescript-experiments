# AvlTree

A persistent sorted map built on an AVL tree, with a thin mutable wrapper. It does what
[`BTree`](../BTree.resi) does -- positional access, a diff that skips whatever two trees share,
snapshots -- at close to `Belt.Map`'s speed for point reads and writes.

It lives in the B-tree's package for now, under the same namespace: `ResBTree.AvlTree` and
`ResBTree.MutableAvlTree`.

```rescript
module IntCmp = Belt.Id.MakeComparable({
  type t = int
  let cmp = (a: int, b: int) => a - b
})

let before = ResBTree.AvlTree.fromArray(~id=module(IntCmp), [(1, "one"), (2, "two"), (3, "three")])
let after = before->ResBTree.AvlTree.set(2, "TWO")->ResBTree.AvlTree.remove(3)

ResBTree.AvlTree.getAt(after, 1) // Some((2, "TWO"))
ResBTree.AvlTree.indexOf(after, 2) // Some(1)

ResBTree.AvlTree.diff(
  before,
  after,
  ~onlyLeft=(key, _) => Console.log2("removed", key), // removed 3
  ~different=(key, _, _) => Console.log2("changed", key), // changed 2
)
```

The API is `BTree`'s without `maxNodeSize`, which means nothing for a tree with one entry per node.
[`AvlTree.resi`](AvlTree.resi) documents every function.

## Choosing a tree

The package has three trees with this interface; see the [package README](../../README.md). Measured
on 1,000 to 100,000 random `int` keys, each benchmark alone in five processes (the measurements are
below the table). The ranges span the three sizes, and any one figure can move by 10% between
recordings.

| Operation                              | `AvlTree` against `Belt.Map` | `AvlTree` against `BTree`  |
| -------------------------------------- | ---------------------------- | -------------------------- |
| `get`                                  | 1.1x to 1.2x slower          | 1.1x faster to 1.7x slower |
| `set`, building from empty             | within about 6% either way   | 1.3x faster to 1.2x slower |
| `set`, overwriting                     | within about 6% either way   | 1.1x faster to 1.3x slower |
| `set`, inserting                       | within about 7% either way   | 1.1x to 1.3x faster        |
| `remove`                               | 1.4x faster                  | 1.1x to 2x faster          |
| `forEach`                              | within about 6% either way   | level to 1.2x slower       |
| `reduce`                               | 1.4x faster to 1.05x slower  | 1.6x to 7x slower          |
| `toArray`                              | 1.5x to 2.1x faster          | 1.1x to 2.2x faster        |
| `keysArray`                            | 1.75x to 2.2x faster         | 1.4x to 2.3x slower        |
| `getAt`                                |                              | 1.5x to 2x slower          |
| `indexOf`                              |                              | 1.3x to 2.1x slower        |
| `diff`, 10 overwrites apart            |                              | 1.1x to 1.3x faster        |
| `diff`, 30 mixed edits apart           |                              | 1.3x faster to 1.2x slower |
| `diff`, equal, rebuilt the same way    |                              | 1.8x to 3.3x slower        |
| `diff`, equal, built from sorted input |                              | 6.3x to 7x slower          |

`forEach`, and `toArray` at 1,000 entries, depend on what else has run in the process more than the
rest do: measured after other benchmarks, rather than alone, `forEach` has come out about 2-3x
faster for every tree, and `BTree.toArray` lands in a slow or a fast mode about 1.7x apart.

<details>
<summary>The measurements behind this table</summary>

Each benchmark run alone in several processes (see [`benchmarks/`](../../benchmarks)); regenerate
with `vp run bench:readme` there, after `vp run bench:record`.

<!-- res-bench filter="^(AvlTree|BTree|Belt\.Map)\." relative="AvlTree" -->

|                                                |               BTree |             AvlTree |            Belt.Map |
| ---------------------------------------------- | ------------------: | ------------------: | ------------------: |
| get n=1000                                     |  22.59 µs\* (1.13x) |  19.97 µs\* (1.00x) |  16.40 µs\* (0.82x) |
| get n=10000                                    |    27.14 µs (0.61x) |  44.79 µs\* (1.00x) |  40.58 µs\* (0.91x) |
| get n=100000                                   |  50.28 µs\* (0.59x) |    84.99 µs (1.00x) |  70.68 µs\* (0.83x) |
| set (build) n=1000                             |   160.33 µs (1.34x) |   119.48 µs (1.00x) |   122.56 µs (1.03x) |
| set (build) n=10000                            |     2.39 ms (1.12x) |     2.12 ms (1.00x) |     2.07 ms (0.97x) |
| set (build) n=100000                           |  35.79 ms\* (0.84x) |  42.47 ms\* (1.00x) |    39.94 ms (0.94x) |
| set (overwrite) n=1000                         |   110.81 µs (1.06x) |   104.33 µs (1.00x) |    98.41 µs (0.94x) |
| set (overwrite) n=10000                        |   138.55 µs (0.85x) |   163.58 µs (1.00x) |   161.76 µs (0.99x) |
| set (overwrite) n=100000                       |   186.50 µs (0.77x) |   242.34 µs (1.00x) |   249.86 µs (1.03x) |
| set (insert) n=1000                            |   188.09 µs (1.32x) | 142.91 µs\* (1.00x) |   146.07 µs (1.02x) |
| set (insert) n=10000                           |   199.48 µs (1.11x) |   179.82 µs (1.00x) | 175.83 µs\* (0.98x) |
| set (insert) n=100000                          |   230.26 µs (1.06x) |   217.94 µs (1.00x) |   203.87 µs (0.94x) |
| remove n=1000                                  |   192.14 µs (1.96x) |  97.84 µs\* (1.00x) | 139.06 µs\* (1.42x) |
| remove n=10000                                 |   230.29 µs (1.27x) |   181.60 µs (1.00x) |   249.70 µs (1.38x) |
| remove n=100000                                | 279.03 µs\* (1.10x) | 253.58 µs\* (1.00x) |   345.15 µs (1.36x) |
| forEach n=1000                                 |     8.29 µs (0.99x) |   8.33 µs\* (1.00x) |     8.51 µs (1.02x) |
| forEach n=10000                                |    83.39 µs (0.95x) |    87.67 µs (1.00x) |    92.50 µs (1.06x) |
| forEach n=100000                               |   828.87 µs (0.85x) |   979.82 µs (1.00x) |     1.03 ms (1.05x) |
| reduce n=1000                                  |   677.08 ns (0.24x) |     2.80 µs (1.00x) |   3.99 µs\* (1.42x) |
| reduce n=10000                                 |     9.02 µs (0.14x) |    65.16 µs (1.00x) |    75.17 µs (1.15x) |
| reduce n=100000                                |   575.48 µs (0.62x) | 932.61 µs\* (1.00x) |   886.13 µs (0.95x) |
| toArray n=1000                                 |    13.29 µs (2.17x) |     6.13 µs (1.00x) |   9.15 µs\* (1.49x) |
| toArray n=10000                                | 123.66 µs\* (1.53x) |  80.73 µs\* (1.00x) |   166.09 µs (2.06x) |
| toArray n=100000                               |   1.69 ms\* (1.09x) |   1.54 ms\* (1.00x) |     2.30 ms (1.49x) |
| keysArray n=1000                               |     2.73 µs (0.71x) |   3.82 µs\* (1.00x) |     6.69 µs (1.75x) |
| keysArray n=10000                              |    28.11 µs (0.44x) |  64.56 µs\* (1.00x) |   140.09 µs (2.17x) |
| keysArray n=100000                             |   504.56 µs (0.52x) |   975.63 µs (1.00x) |   1.74 ms\* (1.78x) |
| getAt n=1000                                   |  18.53 µs\* (0.65x) |  28.36 µs\* (1.00x) |                     |
| getAt n=10000                                  |  30.38 µs\* (0.50x) |    60.59 µs (1.00x) |                     |
| getAt n=100000                                 |  50.00 µs\* (0.49x) |   101.42 µs (1.00x) |                     |
| indexOf n=1000                                 |  20.38 µs\* (0.79x) |  25.69 µs\* (1.00x) |                     |
| indexOf n=10000                                |    26.59 µs (0.48x) |    55.05 µs (1.00x) |                     |
| indexOf n=100000                               |    48.64 µs (0.53x) |    92.59 µs (1.00x) |                     |
| diff (10 overwrites) n=1000                    |   473.17 ns (1.14x) |   416.49 ns (1.00x) |                     |
| diff (10 overwrites) n=10000                   |   843.16 ns (1.16x) |   728.45 ns (1.00x) |                     |
| diff (10 overwrites) n=100000                  |     1.28 µs (1.28x) |   997.06 ns (1.00x) |                     |
| diff (30 mixed edits) n=1000                   |     1.39 µs (0.83x) |     1.67 µs (1.00x) |                     |
| diff (30 mixed edits) n=10000                  |     2.58 µs (1.29x) |     2.00 µs (1.00x) |                     |
| diff (30 mixed edits) n=100000                 |     3.18 µs (1.14x) |   2.80 µs\* (1.00x) |                     |
| diff (equal, rebuilt the same way) n=1000      |     4.00 µs (0.56x) |     7.19 µs (1.00x) |                     |
| diff (equal, rebuilt the same way) n=10000     |    42.39 µs (0.37x) |   113.39 µs (1.00x) |                     |
| diff (equal, rebuilt the same way) n=100000    |   425.33 µs (0.30x) |   1.42 ms\* (1.00x) |                     |
| diff (equal, built from sorted input) n=1000   |     4.19 µs (0.16x) |    26.44 µs (1.00x) |                     |
| diff (equal, built from sorted input) n=10000  |    43.20 µs (0.15x) |   290.85 µs (1.00x) |                     |
| diff (equal, built from sorted input) n=100000 |   460.38 µs (0.14x) |     3.21 ms (1.00x) |                     |

Median time per call. In brackets, each time's multiple of AvlTree's. \* marks a benchmark whose
processes landed more than 10% apart. Measured with each benchmark in 5 processes of its own, with
Node v24.22.0 on Apple M2 Pro, 2026-10-16.

<!-- /res-bench -->

</details>

`BTree` was rebuilt after this tree was written, and now leads on most reads from 10,000 entries up,
though not on point edits, diffs of a few edits, or `toArray`. Reach for `AvlTree` when the work is
mostly inserting and removing keys and diffing trees a few edits apart; for
[`ChunkTree`](../chunk/README.md) for a mix (it is 1.1-1.8x slower to insert and remove, level on
`get` and `forEach`, level or faster on diffs, and faster at positional access and building arrays);
and for `BTree` when reads dominate.

## How it works

### The node

One entry per node, in [`internal/AvlNode.res`](internal/AvlNode.res):

```rescript
type rec t<'k, 'v> = {
  key: 'k,
  value: 'v,
  height: int,
  size: int,
  left: option<t<'k, 'v>>,
  right: option<t<'k, 'v>>,
}
```

The shape and the balancing follow `Belt.Map`'s own tree (`Belt_internalAVLtree`):

- An empty subtree is `None`, which compiles to `undefined`, so there is no wrapper object and a
  leaf is a node with two `undefined` children.
- Sibling heights may differ by up to 2, not the textbook 1. The tree can be a little taller in the
  worst case, and in exchange rotates noticeably less often.
- Nodes are never mutated. `set` and `remove` rebuild the nodes on the path from the root to the
  key, plus the few a rotation touches, and share every other node with the tree they started from.

The one addition to Belt's node is `size`, the number of entries in the subtree. Three things rest
on it:

- `size` on a whole tree is `O(1)`: it is the root's.
- `getAt` and `indexOf` are `O(log n)`. Descending, the size of a node's left subtree says how many
  entries sort before it.
- `diff` uses it to keep two differently shaped trees lined up (below).

### Diffing

[`internal/AvlDiff.res`](internal/AvlDiff.res) reports where two trees differ, in ascending key
order. Its rule is that a subtree which is the same object on both sides (`===`) is skipped without
being looked inside. Since an edit only rebuilds one path, two trees a few edits apart share almost
everything, and a diff costs roughly `O(edits * height)` rather than `O(size)`.

It compares a pair of subtrees in one of two ways. These are the same two that
`Base.Map.fold_symmetric_diff` uses, which is what Jane Street's `Incr_map` is built on.

**In step.** If the two roots hold the same key, the two left subtrees cover exactly the same range
of keys, and so do the two right subtrees. Each pair can then be compared on its own, by plain
recursion, with no state to keep. Related trees are mostly this shape: an overwrite never changes
it, and an insertion or removal only changes it where it rotates or replaces a node's key.

**With cursors.** Where the roots' keys differ, that subtree pair is walked with two in-order
cursors, each a stack of pending items (a whole subtree, or one node's entry). The difficulty is
that a rotation moves a subtree to a different depth, so one side can have a subtree pending whole
while the other still has it buried inside a larger one. `size` settles which to open: a subtree can
only be identical to one of the same size, so the larger of two pending subtrees is opened and the
smaller kept whole, to be matched against whatever comes out. This works for any two trees, related
or not.

`sharedSubtreeCount` runs the same code and counts the skips, so a test can confirm that sharing is
real, not just that the answer is right.

### The mutable wrapper

[`MutableAvlTree`](MutableAvlTree.resi) is one mutable cell holding the latest `AvlTree.t`. `set`
and `remove` store the persistent operation's result back into it. `snapshot` hands out the current
`AvlTree.t` in `O(1)`, and it stays valid however the mutable tree is edited afterwards, so "what
changed since then" is `AvlTree.diff` on two snapshots.

## Optimizations

Each of these was kept because a benchmark showed it mattered. A few things that looked promising
and measured no better were left out.

- **Edits skip rebalancing where nothing changed height.** Most nodes on the path of an edit sit
  above the point where the tree stopped changing height. Each of those is rebuilt with its old
  height and a size the caller already knows (one more, one fewer, or the same), without reading the
  subtree on the other side at all. Only where a subtree's height did change is the balancing code
  reached. This took `set` and `remove` from 1.2x-1.3x slower than `Belt.Map` to about level,
  despite the extra field to maintain.
- **A `set` that changes nothing returns the same tree.** If the key already holds that exact value
  (`===`), every node on the way back up sees its child unchanged and returns itself. No allocation,
  and the result still shares everything with the original, so a later `diff` skips it in one step.
- **`fromArray` builds sorted input in `O(n)`.** Input already in strictly ascending key order is
  split recursively at its midpoint into a perfectly balanced tree, with no comparisons beyond the
  one pass that checks the order. Anything else falls back to repeated `set`.
- **`forEach` and `reduce` keep an explicit stack.** One loop making one call per entry (the
  callback) measured 10-15% faster than a recursive function making two.
- **Array builders write into place.** `toArray`, `keysArray` and `valuesArray` allocate the result
  at its final length and write each entry at its index, which is the running offset plus the size
  of the node's left subtree. They also check a child before recursing into it: a tree of `n`
  entries has `n + 1` empty subtrees, so that halves the calls.
- **`diff` allocates nothing per node.** The cursors are pairs of parallel arrays indexed by a
  counter, not stacks of item records, and one pair serves a whole diff. Recursing in step, when the
  roots agree, avoids the cursors entirely, and made diffs 3x to 6x faster wherever the two trees
  have the same shape.
- **The cursor walk is kept out of the recursive function.** With a single caller the ReScript
  compiler inlines it into the in-step recursion, and V8 then optimizes the loop poorly: about 1.6x
  slower on two differently shaped 100,000-entry trees. It has a second call site for that reason,
  noted where it happens.

### What is left

Two gaps come from the shape of the tree rather than the code:

- A traversal of a tree too big for the cache follows one pointer per entry, where a B-tree reads a
  leaf's worth at a time. That is the `forEach` result at 100,000 entries.
- `getAt` descends about 17 levels on 100,000 entries, where the B-tree descends 4.

And one from the node: it has six fields to Belt's five, so each rebuilt node is a little larger.
That is the likeliest source of the few percent left on `set` when building large trees. Two changes
would remove the extra field: packing `height` into `size`, which hasn't been tried, and balancing
by weight so that `height` isn't needed at all, which has.

### Weight balancing: tried once, not adopted

A variant of this tree balanced on subtree sizes, the way Haskell's `Data.Map` is (a node is
balanced when neither subtree is more than 3 times the size of the other), was built as a drop-in
with the same API and benchmarked next to this one in the same process. It passed the same tests.
Compared with the AVL tree:

- Building a tree by repeated `set` was about 5% faster at 100,000 entries, 1-3% faster at 10,000,
  and 3-8% slower at 1,000. That brought the large build level with `Belt.Map`.
- Overwriting `set` and `remove` were within about 5% either way.
- The two trees came out the same depth: a `get` on 100,000 random keys averaged 16.2 comparisons in
  both.

Those differences are smaller than the 10-15% the benchmarks move from run to run, so the AVL tree
was kept, as the easier of the two to reason about.

This was a quick look, not a settled result, and it would need a more careful evaluation before
drawing a conclusion either way:

- Each figure comes from two runs on one machine, with random `int` keys only. Sorted or clustered
  insertion orders, and keys that are expensive to compare, weren't measured.
- Reads and iteration appeared 10-20% faster in the variant, which a smaller node could explain, but
  it ran first in every pair and an order effect of that size has shown up in these benchmarks
  before. Telling the two apart needs the order alternated or each side run in its own process.
- Only one set of balance parameters was tried, and removal always promoted the successor rather
  than choosing from the larger side as `Data.Map` does.
- Memory use, the more direct benefit of a smaller node, wasn't measured at all.

## Testing

In [`tests/avl/`](../../tests/avl):

- `AvlTree_test.res` covers each operation, then cross-checks long random sequences of inserts,
  overwrites and removals against `Belt.Map.Int`, running `checkInvariants` after every edit.
- `AvlTree_diff_test.res` checks diffs against a slow, obvious comparison, including after edits
  that rotate, and counts how many entries a diff compares to confirm it really skips what is
  shared.
- `AvlNode_test.res` builds nodes by hand to confirm `checkInvariants` rejects each kind of broken
  tree and accepts valid but unusual ones.
- `MutableAvlTree_test.res` covers what is specific to mutability: shared references and snapshots.

## Benchmarks

From [`benchmarks/`](../../benchmarks), `AvlTree` alongside `BTree` and `Belt.Map`:

```bash
vp run bench "^(AvlTree|BTree|Belt\.Map)\."
```

It measures every operation on each, on a bundled, minified build, and ends with a table of them
side by side. See that directory's README for the other trees, more reliable numbers, and how to
read the output.
