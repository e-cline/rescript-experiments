/***
Diffing two AVL trees. `diff` and `sharedSubtreeCount` are the only two functions
`AvlTree.res` needs from this module; the cursor they're both built on is implementation
detail.

Both trees must have been created with the same (or an equivalent) comparator.
`AvlTree.diff` enforces this at the type level (both trees must share the same `Belt.Id`
identity), so nothing here needs to check it again at runtime.
*/

/**
Computes the difference between the two trees, reporting it via the supplied callbacks:
`onlyLeft`/`onlyRight` for keys found on only one side, and `different` for a key present on
both sides with unequal values (compared with `valueEqual`). Reports in ascending key order.
Neither tree is modified.

Subtrees that are the exact same object (`===`) in both trees are skipped without being
looked inside, which is what keeps this cheap for two trees that share most of their
structure -- see `AvlDiff.res`.
*/
let diff: (
  AvlNode.tree<'k, 'v>,
  AvlNode.tree<'k, 'v>,
  ~compare: ('k, 'k) => int,
  ~valueEqual: ('v, 'v) => bool,
  ~onlyLeft: ('k, 'v) => unit,
  ~onlyRight: ('k, 'v) => unit,
  ~different: ('k, 'v, 'v) => unit,
) => unit

/**
Counts how many subtrees `diff` would skip whole (by reference) when comparing the two
trees, without reporting anything else. A diagnostic for verifying (e.g. in tests) that two
trees derived from a common ancestor actually do share structure.
*/
let sharedSubtreeCount: (
  AvlNode.tree<'k, 'v>,
  AvlNode.tree<'k, 'v>,
  ~compare: ('k, 'k) => int,
) => int
