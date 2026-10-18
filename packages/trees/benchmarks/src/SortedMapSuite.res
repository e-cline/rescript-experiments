/***
One set of benchmarks for any persistent sorted map, so that every implementation is measured the
same way: `register` measures each operation on each implementation it's given, at each size. The
adapters in `SortedMaps.res` give it the trees this repository has, and `Belt.Map`.

The code here is shared by every implementation, so in a process measuring several of them its call
sites see several kinds of tree, and V8 optimizes them less well than if they saw one. Which
implementation runs first then matters, by 10-20% in some of these benchmarks. Measured one
benchmark per process, as `res-bench` does by default, every implementation is measured as if it
were the only one.

Every benchmark builds its own trees when it runs (see `Mitata.benchWithSetup`), and takes the
functions it calls out of the implementation's module before measuring, so the measured code never
reads a property off a module object. (A module that reaches the bundle as an object of getters,
the way an imported module does, can end up with slow dictionary properties: about 20 ns on every
call.)
*/

open Benchmarking

/**
What a sorted map needs to be measured. `getAt`, `indexOf` and `diff` are optional: an
implementation without them (`Belt.Map`) gives `None`, and those operations aren't measured for it.
*/
module type S = {
  type t<'k, 'v, 'id>
  /** The implementation's name in benchmark names and tables. */
  let name: string
  let make: (~id: Belt.Id.comparable<'k, 'id>) => t<'k, 'v, 'id>
  let fromArray: (~id: Belt.Id.comparable<'k, 'id>, array<('k, 'v)>) => t<'k, 'v, 'id>
  let get: (t<'k, 'v, 'id>, 'k) => option<'v>
  let set: (t<'k, 'v, 'id>, 'k, 'v) => t<'k, 'v, 'id>
  let remove: (t<'k, 'v, 'id>, 'k) => t<'k, 'v, 'id>
  let forEach: (t<'k, 'v, 'id>, ('k, 'v) => unit) => unit
  let reduce: (t<'k, 'v, 'id>, 'acc, ('acc, 'k, 'v) => 'acc) => 'acc
  let toArray: t<'k, 'v, 'id> => array<('k, 'v)>
  let keysArray: t<'k, 'v, 'id> => array<'k>
  let getAt: option<(t<'k, 'v, 'id>, int) => option<('k, 'v)>>
  let indexOf: option<(t<'k, 'v, 'id>, 'k) => option<int>>
  let diff: option<(t<'k, 'v, 'id>, t<'k, 'v, 'id>, ~different: ('k, 'v, 'v) => unit) => unit>
}

type implementation = module(S)

module IntCmp = Belt.Id.MakeComparable({
  type t = int
  let cmp = (a: int, b: int) => a - b
})

let id: Belt.Id.comparable<int, IntCmp.identity> = module(IntCmp)

/**
How many operations each benchmark of a single operation performs per call. Fixed rather than
proportional to the tree's size, so that times for the same operation at different sizes compare
directly.
*/
let probeCount = 1_000

/**
What every benchmark of a tree of `n` keys starts from: the keys `0` to `n - 1` in a random order,
each as its own value, and `probeCount` of them, in another order, to look up, overwrite or remove.
The same for every benchmark of that size, in every run.
*/
type inputs = {keys: array<int>, entries: array<(int, int)>, probes: array<int>}

let inputsOfSize = (n: int): inputs => {
  let random = SeededRandom.make(42.0)
  let keys = SeededRandom.shuffledRange(random, n)
  {
    keys,
    entries: keys->Array.map(key => (key, key)),
    probes: SeededRandom.shuffledRange(random, n)->Array.slice(~start=0, ~end=probeCount),
  }
}

/**
An operation's benchmark for one implementation: given the size of tree to measure it at, its
setup, or `None` if the implementation has no equivalent.
*/
type benchmark = int => option<unit => Mitata.prepared>

/** Every operation, measured on `M`, in the order they're registered. */
module Operations = (M: S) => {
  // By repeated `set` rather than with `fromArray`: `fromArray` may take a different path in each
  // implementation, and a tree's shape affects everything measured on it.
  let build = entries =>
    entries->Array.reduce(M.make(~id), (tree, (key, value)) => M.set(tree, key, value))

  /** A tree of `n` keys and the keys to probe it with. */
  let treeOfSize = n => {
    let {entries, probes} = inputsOfSize(n)
    (build(entries), probes)
  }

  /** Counts the entries two trees hold different values for. */
  let countDifferences = (diff, left, right) => {
    let count = ref(0)
    diff(left, right, ~different=(_, _, _) => count := count.contents + 1)
    Mitata.doNotOptimize(count.contents)
  }

  /** `diff`'s benchmark, against a tree `other` makes from the tree and its inputs. */
  let diffAgainst = (other): benchmark =>
    n =>
      M.diff->Option.map(diff =>
        (): Mitata.prepared => {
          let inputs = inputsOfSize(n)
          let tree = build(inputs.entries)
          let otherTree = other(tree, inputs)
          {measure: () => countDifferences(diff, tree, otherTree)}
        }
      )

  let operations: array<(string, benchmark)> = [
    (
      "get",
      n => Some(
        () => {
          let (tree, probes) = treeOfSize(n)
          let get = M.get
          {
            measure: () => {
              let sum = ref(0)
              for i in 0 to probeCount - 1 {
                switch get(tree, Array.getUnsafe(probes, i)) {
                | Some(value) => sum := sum.contents + value
                | None => ()
                }
              }
              Mitata.doNotOptimize(sum.contents)
            },
          }
        },
      ),
    ),
    // Building a tree from empty: `n` operations per call, not `probeCount`.
    (
      "set (build)",
      n => Some(
        () => {
          let {keys} = inputsOfSize(n)
          let (make, set) = (M.make, M.set)
          {
            measure: () => {
              let current = ref(make(~id))
              for i in 0 to n - 1 {
                let key = Array.getUnsafe(keys, i)
                current := set(current.contents, key, key)
              }
              Mitata.doNotOptimize(current.contents)
            },
          }
        },
      ),
    ),
    // Overwriting keys the tree already holds.
    (
      "set (overwrite)",
      n => Some(
        () => {
          let (tree, probes) = treeOfSize(n)
          let set = M.set
          {
            measure: () => {
              let current = ref(tree)
              for i in 0 to probeCount - 1 {
                current := set(current.contents, Array.getUnsafe(probes, i), -1)
              }
              Mitata.doNotOptimize(current.contents)
            },
          }
        },
      ),
    ),
    // Inserting keys the tree doesn't hold, into a tree that is already large.
    (
      "set (insert)",
      n => Some(
        () => {
          let (tree, probes) = treeOfSize(n)
          let set = M.set
          {
            measure: () => {
              let current = ref(tree)
              for i in 0 to probeCount - 1 {
                current := set(current.contents, n + Array.getUnsafe(probes, i), -1)
              }
              Mitata.doNotOptimize(current.contents)
            },
          }
        },
      ),
    ),
    (
      "remove",
      n => Some(
        () => {
          let (tree, probes) = treeOfSize(n)
          let remove = M.remove
          {
            measure: () => {
              let current = ref(tree)
              for i in 0 to probeCount - 1 {
                current := remove(current.contents, Array.getUnsafe(probes, i))
              }
              Mitata.doNotOptimize(current.contents)
            },
          }
        },
      ),
    ),
    (
      "forEach",
      n => Some(
        () => {
          let (tree, _) = treeOfSize(n)
          let forEach = M.forEach
          {
            measure: () => {
              let sum = ref(0)
              forEach(tree, (_, value) => sum := sum.contents + value)
              Mitata.doNotOptimize(sum.contents)
            },
          }
        },
      ),
    ),
    (
      "reduce",
      n => Some(
        () => {
          let (tree, _) = treeOfSize(n)
          let reduce = M.reduce
          {measure: () => Mitata.doNotOptimize(reduce(tree, 0, (sum, _, value) => sum + value))}
        },
      ),
    ),
    (
      "toArray",
      n => Some(
        () => {
          let (tree, _) = treeOfSize(n)
          let toArray = M.toArray
          {measure: () => Mitata.doNotOptimize(toArray(tree))}
        },
      ),
    ),
    (
      "keysArray",
      n => Some(
        () => {
          let (tree, _) = treeOfSize(n)
          let keysArray = M.keysArray
          {measure: () => Mitata.doNotOptimize(keysArray(tree))}
        },
      ),
    ),
    (
      "getAt",
      n =>
        M.getAt->Option.map(getAt =>
          (): Mitata.prepared => {
            let (tree, probes) = treeOfSize(n)
            {
              measure: () => {
                let sum = ref(0)
                for i in 0 to probeCount - 1 {
                  switch getAt(tree, Array.getUnsafe(probes, i)) {
                  | Some((_, value)) => sum := sum.contents + value
                  | None => ()
                  }
                }
                Mitata.doNotOptimize(sum.contents)
              },
            }
          }
        ),
    ),
    (
      "indexOf",
      n =>
        M.indexOf->Option.map(indexOf =>
          (): Mitata.prepared => {
            let (tree, probes) = treeOfSize(n)
            {
              measure: () => {
                let sum = ref(0)
                for i in 0 to probeCount - 1 {
                  switch indexOf(tree, Array.getUnsafe(probes, i)) {
                  | Some(index) => sum := sum.contents + index
                  | None => ()
                  }
                }
                Mitata.doNotOptimize(sum.contents)
              },
            }
          }
        ),
    ),
    // `diff` in four situations, from trees sharing nearly everything to trees sharing nothing.
    // Trees 10 overwrites apart, sharing everything off the paths to them.
    (
      "diff (10 overwrites)",
      diffAgainst((tree, {probes}) =>
        probes
        ->Array.slice(~start=0, ~end=10)
        ->Array.reduce(tree, (current, key) => M.set(current, key, -1))
      ),
    ),
    // 10 overwrites, 10 removals and 10 insertions, so the trees' shapes differ around the edits as
    // well as their contents.
    (
      "diff (30 mixed edits)",
      diffAgainst((tree, {keys, probes}) => {
        // Keys from `n` up are ones the tree doesn't hold.
        let n = Array.length(keys)
        Belt.Array.range(0, 29)->Array.reduce(tree, (current, i) => {
          let key = Array.getUnsafe(probes, i)
          i < 10
            ? M.set(current, key, -1)
            : i < 20
            ? M.remove(current, key)
            : M.set(current, n + key, -1)
        })
      }),
    ),
    // Equal contents, built again the same way: the same shape, but no node in common.
    ("diff (equal, rebuilt the same way)", diffAgainst((_, {entries}) => build(entries))),
    // Equal contents, built from the entries in ascending order: a different shape too.
    (
      "diff (equal, built from sorted input)",
      diffAgainst((_, {entries}) =>
        M.fromArray(~id, entries->Array.toSorted(((a, _), (b, _)) => Int.toFloat(a - b)))
      ),
    ),
  ]
}

/**
Registers every operation on every one of `implementations`, at each of `sizes`, through
`comparison`, whose implementations should be named as they are.
*/
let register = (comparison: Comparison.t, implementations: array<implementation>, ~sizes) => {
  let byImplementation = implementations->Array.map(implementation => {
    module M = unpack(implementation)
    module Measured = Operations(M)
    (M.name, Measured.operations)
  })
  // Every implementation's list comes from the same functor, so they line up.
  let operationNames = switch byImplementation[0] {
  | Some((_, operations)) => operations->Array.map(((name, _)) => name)
  | None => []
  }
  sizes->Array.forEach(n =>
    operationNames->Array.forEachWithIndex((operation, index) =>
      comparison->Comparison.bench(
        ~operation,
        ~parameter=`n=${Int.toString(n)}`,
        byImplementation->Array.filterMap(
          ((name, operations)) => {
            let (_, benchmark) = Array.getUnsafe(operations, index)
            benchmark(n)->Option.map(setup => (name, setup))
          },
        ),
      )
    )
  )
}
