// See `AtomMap.resi` for what this module does. The implementation is `SignalMap`'s, over
// `ResTrees.BTree`, with a `fromArray` that also takes a node size.
//
// Depends on `@e-cline/res_signals` (`Atom`/`Signal`) and `@e-cline/res_trees`
// (`BTree`, `SortedMap`) -- two other ReScript packages -- directly through ReScript's own
// module system: each namespaces its modules (`ResSignals`/`ResTrees`, per
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
  make(~name?, ~historyLength?, ~id, ResTrees.BTree.fromArray(~id, ~maxNodeSize?, entries))
