/***
Insertion into a `Node` tree. One pass down to the leaf and back up: a node that overflows
on the way back splits in two and hands its right half and the separator between the halves to
its parent, which may overflow in turn.

What each level copies:

- the value was already there (`===`): nothing; the same node comes back, all the way up;
- an overwrite: the leaf's `values`; above it, `links` only;
- a new key: the leaf's `keys` and `values`; above it, `links` only, with the counts from the
  edited child onwards raised by one in the copy;
- a split below: `keys` as well as `links`, once per split.
*/

open Node

/**
What one insertion reports back up the tree besides the node it returns. A single one is made
per `set` (by `BTree.set`, which also deals with a root that split) and threaded through,
so that no level allocates a result record or tuple.
*/
type state<'k, 'v> = {
  // Whether a key was added (rather than a value overwritten).
  mutable grew: bool,
  // After a split: the right half and the separator between the halves. The node returned is the
  // left half. `splitKey` is meaningless while `splitRight` is `None`.
  mutable splitKey: 'k,
  mutable splitRight: option<t<'k, 'v>>,
}

/**
The subtree with `key` set to `value`: `node` itself if `key` already held exactly `value`, and
otherwise a new node. If that node had to split, it is the left half, and `state` holds the rest.
*/
let rec intoNode = (
  node: t<'k, 'v>,
  key: 'k,
  value: 'v,
  compare: ('k, 'k) => int,
  maxNodeSize: int,
  state: state<'k, 'v>,
): t<'k, 'v> => {
  let found = search(node.keys, key, compare)
  if isLeaf(node) {
    if found >= 0 {
      Array.getUnsafe(node.values, found) === value
        ? node
        : leaf(node.keys, ArrayOps.replaceAt(node.values, found, value))
    } else {
      let index = Int.bitwiseNot(found)
      state.grew = true
      let keys = ArrayOps.insertAt(node.keys, index, key)
      let values = ArrayOps.insertAt(node.values, index, value)
      let count = Array.length(keys)
      if count <= maxNodeSize {
        leaf(keys, values)
      } else {
        // The right half's first key is the separator: everything in the left half is below it.
        let middle = Int.shiftRight(count, 1)
        state.splitKey = Array.getUnsafe(keys, middle)
        state.splitRight = Some(
          leaf(ArrayOps.sliceFrom(keys, middle), ArrayOps.sliceFrom(values, middle)),
        )
        leaf(ArrayOps.slice(keys, 0, middle), ArrayOps.slice(values, 0, middle))
      }
    }
  } else {
    let oldLinks = node.links
    let index = childIndex(found)
    let child = childAt(oldLinks, index)
    let newChild = intoNode(child, key, value, compare, maxNodeSize, state)
    if newChild === child {
      node
    } else {
      switch state.splitRight {
      | None =>
        let links = ArrayOps.copy(oldLinks)
        setChild(links, index, newChild)
        if state.grew {
          addToCounts(links, index, 1)
        }
        internal(node.keys, links)
      | Some(right) =>
        state.splitRight = None
        let before = index == 0 ? 0 : countAt(oldLinks, index - 1)
        let keys = ArrayOps.insertAt(node.keys, index, state.splitKey)
        let links = ArrayOps.replaceTwoWithFour(
          oldLinks,
          Int.shiftLeft(index, 1),
          Child(newChild),
          Count(before + size(newChild)),
          Child(right),
          Count(countAt(oldLinks, index) + 1),
        )
        addToCounts(links, index + 2, 1)
        let children = childCount(links)
        if children <= maxNodeSize {
          internal(keys, links)
        } else {
          // Unlike a leaf's, the middle separator moves up rather than staying in either half:
          // separators are routing information only.
          let middle = Int.shiftRight(children, 1)
          let rightLinks = ArrayOps.sliceFrom(links, Int.shiftLeft(middle, 1))
          addToCounts(rightLinks, 0, -countAt(links, middle - 1))
          state.splitKey = Array.getUnsafe(keys, middle - 1)
          state.splitRight = Some(internal(ArrayOps.sliceFrom(keys, middle), rightLinks))
          internal(
            ArrayOps.slice(keys, 0, middle - 1),
            ArrayOps.slice(links, 0, Int.shiftLeft(middle, 1)),
          )
        }
      }
    }
  }
}
