# @e-cline/res_b_tree

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
are in [`benchmarks/README.md`](benchmarks/README.md#results), and the details in each tree's
section below and in [`src/avl/README.md`](src/avl/README.md) and
[`src/chunk/README.md`](src/chunk/README.md).

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/res_b_tree rescript @rescript/runtime
```

Add `"@e-cline/res_b_tree"` to the `dependencies` in your `rescript.json`. The modules are under the
`ResBTree` namespace (`ResBTree.BTree.make`), and your project's `rescript build` compiles them
along with your own code.

## Layout

The public modules are `BTree`, `AvlTree` and `ChunkTree`, each with a `Mutable` wrapper, and each
with a `.resi` that keeps its tree type opaque. Everything else is implementation, in an `internal/`
directory next to the tree it belongs to:

- **`src/`**: `BTree` and `MutableBTree`, with `internal/` holding the B+tree's node (`Node`),
  insertion (`Insert`), removal (`Delete`), diff (`Diff`) and array helpers (`ArrayOps`).
- **[`src/avl/`](src/avl)**: `AvlTree` and `MutableAvlTree`.
- **[`src/chunk/`](src/chunk)**: `ChunkTree` and `MutableChunkTree`.
- **`tests/`**: the tests for each tree, plus
  [`tests/candidates/Conformance.res`](tests/candidates/Conformance.res), one suite that any tree
  with `AvlTree`'s interface can be run through.
- **[`benchmarks/`](benchmarks)**: a separate, unpublished package measuring each tree against
  `Belt.Map` and against each other, on a bundled and minified build.

Each `Mutable` wrapper is one mutable cell holding the latest persistent tree: `set`/`remove` call
the persistent operation and store the result back. That gets in-place-feeling mutation without a
second implementation, and its `snapshot()` is `O(1)` and always safe to hold onto, so "what changed
since then" is `diff` on two snapshots.

## How `BTree` works

A B+tree: entries live in the leaves, and internal nodes hold separator keys for routing.
`maxNodeSize` (default 32, clamped to 4-256) is the most keys a leaf, or children an internal node,
may hold, and every node but the root holds at least half that. `internal/Node.res` describes the
node in full; the choices that matter for speed are:

- **One record shape for leaves and internal nodes**, `{keys, values, links}`, with the fields a
  kind doesn't use holding one shared empty array. Every field read in a descent sees one hidden
  class, and "is this a leaf" is a pointer comparison.
- **Leaves are two parallel arrays**, `keys` and `values`, rather than an array of `(key, value)`
  tuples: no extra object to load per key while searching, and no new tuple per write.
- **An internal node's children and their cumulative entry counts share one array**:
  `links = [child0, count0, child1, count1, ...]`. An edit below a node copies exactly that one
  array, and reuses `keys` unless a child split, borrowed or merged. `getAt` binary-searches the
  counts; `indexOf` reads one count per level.
- **An overwrite copies a leaf's `values` and keeps its `keys`**, and setting a key to the value it
  already holds returns the same tree.
- **Every node array is packed and exactly sized**, built with `slice`, `toSpliced` or `concat`. An
  array made with `new Array(n)` and then filled stays `HOLEY` in V8 for good, and so does every
  array copied from it.
- **A search within a node halves down to 8 keys, then scans** with an early exit.
- **No function on a hot path has a single caller**, because the minifier inlines such a function as
  an immediately-called function expression, which V8 was seen to allocate a closure for on every
  call. See the note at the top of `BTree.res`.

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

## Performance history

`BTree` was rebuilt in October 2026. The first version was written to be easy to read: leaves of
`(key, value)` tuples, three arrays per internal node (`separators`, `children`, `sizes`), arrays
filled after `new Array(n)`, and a diff that walked every entry of each changed leaf through an
allocating cursor. A survey of other persistent sorted maps and of V8's handling of objects and
arrays pointed at each of those, and a redesigned B+tree was prototyped and measured against the AVL
tree through a shared harness before replacing it. Against the AVL tree, before and after (1,000 /
10,000 / 100,000 entries):

| Operation                   | Before             | After              |
| --------------------------- | ------------------ | ------------------ |
| `get`                       | 2.27 / 1.41 / 1.14 | 0.86 / 0.49 / 0.52 |
| `set`, overwriting          | 1.56 / 1.16 / 1.10 | 1.01 / 0.83 / 0.81 |
| `remove`                    | 1.76 / 1.38 / 1.25 | 1.90 / 1.26 / 1.12 |
| `reduce`                    | 2.34 / 1.27 / 0.98 | 0.22 / 0.13 / 0.11 |
| `indexOf`                   | 2.49 / 1.96 / 1.68 | 0.79 / 0.45 / 0.48 |
| `diff`, 10 overwrites apart | 21 / 24 / 32       | 1.16 / 1.23 / 1.34 |
| `diff`, 30 mixed edits      | 9.8 / 14 / 18      | 0.81 / 1.36 / 1.23 |

Times are relative to `AvlTree` (below 1.00 is faster), each the mean of two runs with the
measurement order swapped. Against `Belt.Map`, measured the same way at the time, `BTree` was
1.3-2.1x faster on `get`, 6-11x faster on `reduce` and 1.6-3x on `toArray`, within 1.3x either way
on `set`, and 1.1-2.1x slower on `remove`. Current measurements, each benchmark run alone, are in
[`benchmarks/README.md`](benchmarks/README.md#results).

Removal is the operation the redesign didn't improve. Rebalancing is the textbook kind (a node below
half full borrows one entry from a sibling or merges with it), so emptying a small tree rebalances
on most removals; a lower minimum would help, and hasn't been tried.

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

`BTree_test.res`, `BTree_diff_test.res` and `MutableBTree_test.res` test the public API directly,
including the `maxNodeSize` clamp boundaries and that two bindings to one `MutableBTree.t` observe
each other's writes.
