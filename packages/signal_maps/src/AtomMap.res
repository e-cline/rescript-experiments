// See `AtomMap.resi` for what this module does. The implementation is `SignalMap`'s, over
// `Trees.BTree`, with a `fromArray` that also takes a node size.
//
// Depends on `@e-cline/signals` (`Atom`/`Signal`) and `@e-cline/trees`
// (`BTree`, `SortedMap`) -- two other ReScript packages -- directly through ReScript's own
// module system: each namespaces its modules (`Signals`/`Trees`, per
// their own `rescript.json`'s `"namespace"`), so `Atom`/`Signal`/`BTree` aren't
// visible to another package unqualified -- opened (or qualified) in every file
// in this package that needs them.

include SignalMap.MakeAtomMap(MapTree.BTree, ComputedMap)

let fromArray = (
  ~name: option<string>=?,
  ~historyLength: option<int>=?,
  ~maxNodeSize: option<int>=?,
  ~id: Belt.Id.comparable<'k, 'id>,
  entries: array<('k, 'v)>,
): t<'k, 'v, 'id> =>
  make(~name?, ~historyLength?, ~id, Trees.BTree.fromArray(~id, ~maxNodeSize?, entries))
