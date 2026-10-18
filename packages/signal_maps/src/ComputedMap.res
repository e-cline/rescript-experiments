// See `ComputedMap.resi` for what this module does. The implementation is `SignalMap`'s, over
// `Trees.BTree` (`MapTree.BTree` carries a source tree's node size over to what's derived
// from it).

include SignalMap.MakeComputedMap(MapTree.BTree)
