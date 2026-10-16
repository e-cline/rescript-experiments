/***
Removal from a `Node` tree. One pass down to the leaf and back up: a node left with fewer
than `minNodeSize` keys or children is put right by its parent on the way back, either by moving
one over from a sibling that has more than the minimum, or by merging it with a sibling (which
takes a child from the parent, and may leave it too small in turn).

A key that isn't there costs no allocation: the same node comes back, all the way up. Otherwise
each level without a borrow or merge copies `links` alone (lowering the counts from the edited
child onwards by one in the copy), and reuses `keys`.
*/

open Node

/** Adds `delta` to the count of the child at `index` alone, in place. */
let addToCount = (links: array<link<'k, 'v>>, index: int, delta: int): unit =>
  setCount(links, index, countAt(links, index) + delta)

/**
`node` with its children at `index - 1` and `index` replaced, after one key or child was moved
from the end of the left one to the start of `child` (the right one, which had just lost an
entry and fallen below the minimum).
*/
let borrowFromLeft = (node: t<'k, 'v>, index: int, child: t<'k, 'v>): t<'k, 'v> => {
  let left = childAt(node.links, index - 1)
  let links = ArrayOps.copy(node.links)
  addToCounts(links, index, -1)
  if isLeaf(left) {
    let last = Array.length(left.keys) - 1
    let movedKey = Array.getUnsafe(left.keys, last)
    setChild(
      links,
      index - 1,
      leaf(ArrayOps.slice(left.keys, 0, last), ArrayOps.slice(left.values, 0, last)),
    )
    setChild(
      links,
      index,
      leaf(
        ArrayOps.insertAt(child.keys, 0, movedKey),
        ArrayOps.insertAt(child.values, 0, Array.getUnsafe(left.values, last)),
      ),
    )
    addToCount(links, index - 1, -1)
    // The moved key is now the smallest on the right, which makes it the boundary.
    internal(ArrayOps.replaceAt(node.keys, index - 1, movedKey), links)
  } else {
    let leftLinks = left.links
    let last = childCount(leftLinks) - 1
    let movedSize = countAt(leftLinks, last) - countAt(leftLinks, last - 1)
    let childLinks = ArrayOps.insertTwoAt(
      child.links,
      0,
      Child(childAt(leftLinks, last)),
      Count(movedSize),
    )
    addToCounts(childLinks, 1, movedSize)
    setChild(
      links,
      index - 1,
      internal(
        ArrayOps.slice(left.keys, 0, last - 1),
        ArrayOps.slice(leftLinks, 0, Int.shiftLeft(last, 1)),
      ),
    )
    // The separator between the two siblings comes down to sit between the moved child and the
    // right sibling's old first child, and the left sibling's last separator goes up in its place.
    setChild(
      links,
      index,
      internal(ArrayOps.insertAt(child.keys, 0, Array.getUnsafe(node.keys, index - 1)), childLinks),
    )
    addToCount(links, index - 1, -movedSize)
    internal(ArrayOps.replaceAt(node.keys, index - 1, Array.getUnsafe(left.keys, last - 1)), links)
  }
}

/**
The mirror of `borrowFromLeft`: `node` with its children at `index` and `index + 1` replaced,
after one key or child was moved from the start of the right one to the end of `child`.
*/
let borrowFromRight = (node: t<'k, 'v>, index: int, child: t<'k, 'v>): t<'k, 'v> => {
  let right = childAt(node.links, index + 1)
  let links = ArrayOps.copy(node.links)
  addToCounts(links, index, -1)
  if isLeaf(right) {
    let end = Array.length(child.keys)
    setChild(
      links,
      index,
      leaf(
        ArrayOps.insertAt(child.keys, end, Array.getUnsafe(right.keys, 0)),
        ArrayOps.insertAt(child.values, end, Array.getUnsafe(right.values, 0)),
      ),
    )
    setChild(
      links,
      index + 1,
      leaf(ArrayOps.sliceFrom(right.keys, 1), ArrayOps.sliceFrom(right.values, 1)),
    )
    addToCount(links, index, 1)
    // The boundary is the smallest key remaining on the right.
    internal(ArrayOps.replaceAt(node.keys, index, Array.getUnsafe(right.keys, 1)), links)
  } else {
    let rightLinks = right.links
    let movedSize = countAt(rightLinks, 0)
    let remainingLinks = ArrayOps.sliceFrom(rightLinks, 2)
    addToCounts(remainingLinks, 0, -movedSize)
    setChild(
      links,
      index,
      internal(
        ArrayOps.insertAt(child.keys, Array.length(child.keys), Array.getUnsafe(node.keys, index)),
        ArrayOps.insertTwoAt(
          child.links,
          Array.length(child.links),
          Child(childAt(rightLinks, 0)),
          Count(size(child) + movedSize),
        ),
      ),
    )
    setChild(links, index + 1, internal(ArrayOps.sliceFrom(right.keys, 1), remainingLinks))
    addToCount(links, index, movedSize)
    internal(ArrayOps.replaceAt(node.keys, index, Array.getUnsafe(right.keys, 0)), links)
  }
}

/**
`node` with its children at `index` and `index + 1` replaced by the two of them merged into one.
`left` and `right` are those two children as they now stand (one of them has just lost an entry).
A merged leaf drops the separator that was between the two; a merged internal node keeps it,
between what were the left's last child and the right's first.
*/
let merge = (node: t<'k, 'v>, index: int, left: t<'k, 'v>, right: t<'k, 'v>): t<'k, 'v> => {
  let merged = if isLeaf(left) {
    leaf(ArrayOps.concat(left.keys, right.keys), ArrayOps.concat(left.values, right.values))
  } else {
    let links = ArrayOps.concat(left.links, right.links)
    addToCounts(links, childCount(left.links), size(left))
    internal(ArrayOps.concat3(left.keys, [Array.getUnsafe(node.keys, index)], right.keys), links)
  }
  // The pair's count is that of its right member, less the entry removed.
  let links = ArrayOps.replaceFourWithTwo(
    node.links,
    Int.shiftLeft(index, 1),
    Child(merged),
    Count(countAt(node.links, index + 1) - 1),
  )
  addToCounts(links, index + 1, -1)
  internal(ArrayOps.removeAt(node.keys, index), links)
}

/**
`node` after its child at `index` became `child`, one entry lighter and now below the minimum.
Borrowing is preferred to merging (it leaves `node` the same width), and the left sibling to the
right.
*/
let rebalance = (node: t<'k, 'v>, index: int, child: t<'k, 'v>, minNodeSize: int): t<'k, 'v> => {
  let links = node.links
  let last = childCount(links) - 1
  if index > 0 && width(childAt(links, index - 1)) > minNodeSize {
    borrowFromLeft(node, index, child)
  } else if index < last && width(childAt(links, index + 1)) > minNodeSize {
    borrowFromRight(node, index, child)
  } else if index > 0 {
    merge(node, index - 1, childAt(links, index - 1), child)
  } else {
    merge(node, index, child, childAt(links, index + 1))
  }
}

/**
The subtree without `key`: `node` itself if `key` isn't in it, and otherwise a new node, which
may be below the minimum size (its caller checks; for the root, that is `BTree.remove`).
*/
let rec fromNode = (node: t<'k, 'v>, key: 'k, compare: ('k, 'k) => int, minNodeSize: int): t<
  'k,
  'v,
> => {
  let found = search(node.keys, key, compare)
  if isLeaf(node) {
    found >= 0
      ? leaf(ArrayOps.removeAt(node.keys, found), ArrayOps.removeAt(node.values, found))
      : node
  } else {
    let index = childIndex(found)
    let child = childAt(node.links, index)
    let newChild = fromNode(child, key, compare, minNodeSize)
    if newChild === child {
      node
    } else if width(newChild) >= minNodeSize {
      let links = ArrayOps.copy(node.links)
      setChild(links, index, newChild)
      addToCounts(links, index, -1)
      internal(node.keys, links)
    } else {
      rebalance(node, index, newChild, minNodeSize)
    }
  }
}
