# @e-cline/res_trees

Persistent sorted maps for ReScript, each with a mutable wrapper, positional access, and a diff that
skips whatever two trees share.

There are three trees, with the same operations (`BTree` also takes a node size):

| Module                           | Structure                                     | Reach for it when                                                    |
| -------------------------------- | --------------------------------------------- | -------------------------------------------------------------------- |
| `BTree` / `MutableBTree`         | B+tree, up to 32 entries per node             | reads dominate: the fastest `get`, `indexOf`, `getAt` and `reduce`   |
| `ChunkTree` / `MutableChunkTree` | AVL spine with leaves of up to 16 entries     | a mix of edits, diffs and reads: never far from the best at anything |
| `AvlTree` / `MutableAvlTree`     | AVL tree, one entry per node, like `Belt.Map` | small edits and diffs dominate: the cheapest inserts and removals    |

Against `AvlTree`, on random `int` keys from 1,000 to 100,000 entries, `BTree` is 1.6-1.7x faster on
`get` from 10,000 entries up (1.1x slower at 1,000), 1.3-2.1x on `indexOf`, 1.5-2x on `getAt`, and
1.4-7x on `reduce` and `keysArray`, but 1.1-2x slower to insert or remove a key and up to 1.3x
slower on diffs a few edits apart. `ChunkTree` sits between the two: level on `get`, 1.7-2.1x faster
on `getAt`, 1.5-5x on `reduce`, `toArray` and `keysArray`, level or faster on diffs, and 1.1-1.8x
slower to insert or remove. Iterating with a callback (`forEach`) is within 1.2x across all three,
and is the measurement most moved by whatever else has run in the process, by up to 3x. The numbers
are in [`benchmarks/README.md`](benchmarks/README.md#results), and the details in each tree's own
README: [`src/btree/`](src/btree/README.md), [`src/avl/`](src/avl/README.md) and
[`src/chunk/`](src/chunk/README.md).

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/res_trees rescript @rescript/runtime
```

Add `"@e-cline/res_trees"` to the `dependencies` in your `rescript.json`. The modules are under the
`ResTrees` namespace (`ResTrees.BTree.make`), and your project's `rescript build` compiles them
along with your own code.

## Layout

The public modules are `BTree`, `AvlTree` and `ChunkTree`, each with a `Mutable` wrapper, and each
with a `.resi` that keeps its tree type opaque. Each tree has a directory of its own under `src/`,
with a README, and everything else is implementation, in an `internal/` directory next to the tree
it belongs to:

- **[`src/btree/`](src/btree)**: `BTree` and `MutableBTree`, with `internal/` holding the B+tree's
  node (`Node`), insertion (`Insert`), removal (`Delete`), diff (`Diff`) and array helpers
  (`ArrayOps`).
- **[`src/avl/`](src/avl)**: `AvlTree` and `MutableAvlTree`.
- **[`src/chunk/`](src/chunk)**: `ChunkTree` and `MutableChunkTree`.
- **`tests/`**: the tests for each tree, in `btree/`, `avl/` and `chunk/` to match `src/`, plus
  [`tests/candidates/Conformance.res`](tests/candidates/Conformance.res), one suite that any tree
  with `AvlTree`'s interface can be run through.
- **[`benchmarks/`](benchmarks)**: a separate, unpublished package measuring each tree against
  `Belt.Map` and against each other, on a bundled and minified build.

Each `Mutable` wrapper is one mutable cell holding the latest persistent tree: `set`/`remove` call
the persistent operation and store the result back. That gets in-place-feeling mutation without a
second implementation, and its `snapshot()` is `O(1)` and always safe to hold onto, so "what changed
since then" is `diff` on two snapshots.

## How each tree works

- **[`BTree`](src/btree/README.md)**: a B+tree with up to `maxNodeSize` (default 32) keys per leaf,
  whose leaves are parallel key and value arrays and whose internal nodes keep children and
  cumulative counts in one array, so an edit copies one array per level.
- **[`AvlTree`](src/avl/README.md)**: one entry per node, height-balanced, with each node caching
  its subtree's size for positional access.
- **[`ChunkTree`](src/chunk/README.md)**: `AvlTree`'s spine with small sorted arrays as leaves.

## Diffing

All three trees diff the same way, adapted to their nodes: two trees are walked in ascending key
order, and a subtree that is the exact same object (`===`) on both sides is skipped without being
looked inside. Since an edit only rebuilds the path from the root to whatever changed, two trees a
few edits apart share almost everything, and a diff costs roughly `O(edits × height)` rather than
`O(size)`.

A pair of subtrees is compared in one of two ways, the same two that Jane Street's
`Base.Map.fold_symmetric_diff` (which `Incr_map` is built on) uses:

- **In step**, while the two subtrees are known to cover the same keys. In `BTree`, that is two
  internal nodes with the same `keys` array (the same separators), whose children are then compared
  pairwise; and two leaves with the same `keys` array (as an overwrite leaves them), whose values
  alone are compared, with no comparator calls.
- **With cursors**, for anything else: an in-order cursor over each side, merging leaves as sorted
  runs and opening the taller of two pending subtrees (in `BTree`; the binary trees use `size`).
  This handles two trees of any shape, related or not, and allocates nothing per entry.

A cursor only ever skips a subtree when the other is skipping the very same node, having consumed
everything before it, so whatever follows a run of shared nodes is still compared. (Dropping those
differences is a published bug in another persistent B-tree's diff; `BTree_structure_test.res` tests
for it.)

`sharedSubtreeCount(left, right)` runs the same walk and counts the skips, so that a test can
confirm two related trees really do share structure, not just that the diff happens to come out
right.

## Belt usage

Keys are identified via `Belt.Id.comparable` (built with `Belt.Id.MakeComparable`), the same
mechanism `Belt.Set`/`Belt.Map` use, rather than a bare `(k, k) => int` function: two trees built
from different comparators can't be passed to `diff`/`sharedSubtreeCount` together, which is a
compile error rather than a wrong answer. Extracting the comparator back out of a
`Belt.Id.comparable` needs the `(type k, type id, ...)` locally-abstract-type idiom to unpack the
first-class module it's built from; see `BTree.make`'s comment.

## Why this has no TypeScript surface

Unlike `res_react_ui`, this package has no `src/index.ts`, no `@genType` annotations, and no
`dist/`: it exists to be used from other ReScript code (so far, only `res_signal_maps`), not to hand
a typed surface to TypeScript. Its `vite.config.ts` therefore passes `typescriptSurface: false` to
`../../vite.config.base.ts`'s `makeRescriptLibConfig`: `build`/`typecheck` become no-ops (so
`vp run -r build`/`vp run -r typecheck` from the repo root don't need to special-case it) and `test`
(`vp test run`) depends on the root-level `res` task (`rescript build`). See the repo-root
`RESCRIPT.md` for why genType was skipped deliberately here, rather than by default.

## Testing

Every test is written directly in ReScript, using
[`rescript-vitest`](https://github.com/cometkim/rescript-vitest). They are named
`<Module>_test.res`, not `<module>.test.res`, so ReScript's PascalCase module naming isn't fought.
`TestSupport.res` holds what they share: an `int` `Belt.Id.comparable` and a seeded
Lehmer/Park-Miller PRNG (see its comment on why the multiply-then-mod runs in `float`).

The strongest coverage comes from three techniques, used for all three trees:

- **`checkInvariants` after every edit.** Each tree's `checkInvariants` walks it and throws a
  descriptive error on any broken structural invariant: keys or separators out of order, a node
  outside its size bounds, a wrong cached count, unbalanced heights, leaves at different depths. The
  stress tests call it after every single mutation, so a structural bug fails at the operation that
  introduced it rather than later, when a wrong `get` happens to surface it. This is only sound if
  `checkInvariants` really rejects broken trees, so `Node_test.res` (and the equivalent tests for
  the other two trees) build broken nodes by hand and check each invariant is caught, and that a
  valid but unusual tree (such as one whose separator no longer equals any key) is not.
- **Oracle stress tests.** Every operation is cross-checked against `Belt.Map.Int`: long random
  sequences of inserts, overwrites and removals, over key spaces small enough that the same keys are
  inserted, overwritten and removed again and again.
- **One conformance suite for every tree.**
  [`tests/candidates/Conformance.res`](tests/candidates/Conformance.res) is a functor over
  `AvlTree`'s interface holding the above plus diff checks (against a plain comparison, in key
  order, and counting how many entries a diff compares, to confirm it really skips what is shared).
  `BTree_structure_test.res` runs it at node sizes 8, 16 and 32, and adds what can only be seen from
  inside: where nodes split, borrow and merge, which arrays an edit reuses, and diffs across runs of
  shared nodes.

Each tree's README lists the tests specific to it.
