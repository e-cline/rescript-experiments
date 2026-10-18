/***
A read-only, sorted, signal-backed map holding a `Trees.BTree.t`, derived from an `AtomMap` or
another `ComputedMap` -- what `mapValues`/`filterMap`/`filter`/`map` return. A derived map's tree
has the same node size as its source's.

Its interface is `SignalMap.ComputedMap`, where each operation is documented. For the same map
over another tree, see `SignalMap.Make`.
*/

include SignalMap.ComputedMap with type tree<'k, 'v, 'id> = Trees.BTree.t<'k, 'v, 'id>
