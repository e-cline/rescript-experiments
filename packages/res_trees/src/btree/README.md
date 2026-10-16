# BTree

A persistent sorted map built on a B+tree, with a thin mutable wrapper. Of the package's three trees
it is the fastest to read from -- `get`, `indexOf`, `getAt` and `reduce` -- and the slowest to
insert into or remove from.

It lives in `res_trees` alongside the other trees, under the same namespace: `ResTrees.BTree` and
`ResTrees.MutableBTree`.

```rescript
module IntCmp = Belt.Id.MakeComparable({
  type t = int
  let cmp = (a: int, b: int) => a - b
})

let before = ResTrees.BTree.fromArray(~id=module(IntCmp), [(1, "one"), (2, "two"), (3, "three")])
let after = before->ResTrees.BTree.set(2, "TWO")->ResTrees.BTree.remove(3)

ResTrees.BTree.getAt(after, 1) // Some((2, "TWO"))
ResTrees.BTree.indexOf(after, 2) // Some(1)

ResTrees.BTree.diff(
  before,
  after,
  ~onlyLeft=(key, _) => Console.log2("removed", key), // removed 3
  ~different=(key, _, _) => Console.log2("changed", key), // changed 2
)
```

`make` and `fromArray` take an optional `~maxNodeSize` (see below). [`BTree.resi`](BTree.resi)
documents every function. For how it compares with the other trees, see the
[package README](../../README.md).

## How it works

A B+tree: entries live in the leaves, and internal nodes hold separator keys for routing.
`maxNodeSize` (default 32, clamped to 4-256) is the most keys a leaf, or children an internal node,
may hold, and every node but the root holds at least half that.
[`internal/Node.res`](internal/Node.res) describes the node in full; the choices that matter for
speed are:

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
  call. See the note at the top of [`BTree.res`](BTree.res).

The diff walks two trees the way the package README's [Diffing](../../README.md#diffing) section
describes. Its in-step case is two internal nodes with the same `keys` array (the same separators),
whose children are then compared pairwise, and two leaves with the same `keys` array (as an
overwrite leaves them), whose values alone are compared, with no comparator calls. Its cursors open
the taller of two pending subtrees.

## Files

- [`BTree.res`](BTree.res) / [`BTree.resi`](BTree.resi): the persistent tree's public API, a thin
  facade over `internal/`.
- [`MutableBTree.res`](MutableBTree.res) / [`MutableBTree.resi`](MutableBTree.resi): the mutable
  wrapper.
- [`internal/Node.res`](internal/Node.res): the node, searching and iterating it, building one from
  sorted entries, and the structural check behind `checkInvariants`.
- [`internal/Insert.res`](internal/Insert.res) and [`internal/Delete.res`](internal/Delete.res):
  insertion with splits, and removal with borrowing and merging.
- [`internal/Diff.res`](internal/Diff.res): the walk behind `diff` and `sharedSubtreeCount`.
- [`internal/ArrayOps.res`](internal/ArrayOps.res): the packed, exactly sized array operations nodes
  are built with.

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
[`benchmarks/README.md`](../../benchmarks/README.md#results).

Removal is the operation the redesign didn't improve. Rebalancing is the textbook kind (a node below
half full borrows one entry from a sibling or merges with it), so emptying a small tree rebalances
on most removals; a lower minimum would help, and hasn't been tried.

## Testing

In [`tests/btree/`](../../tests/btree):

- `BTree_test.res`, `BTree_diff_test.res` and `MutableBTree_test.res` test the public API directly,
  including the `maxNodeSize` clamp boundaries and that two bindings to one `MutableBTree.t` observe
  each other's writes.
- `BTree_structure_test.res` runs the package's conformance suite at node sizes 8, 16 and 32, and
  adds what can only be seen from inside: where nodes split, borrow and merge, which arrays an edit
  reuses, and diffs across runs of shared nodes.
- `Node_test.res` builds broken nodes by hand to confirm `checkInvariants` catches each invariant,
  and that a valid but unusual tree (such as one whose separator no longer equals any key) passes.

## Benchmarks

From [`benchmarks/`](../../benchmarks), `BTree` alongside `AvlTree` and `Belt.Map`:

```bash
vp run bench "^(AvlTree|BTree|Belt\.Map)\."
```
