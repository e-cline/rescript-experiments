/***
Benchmarks for every sorted map in `res_b_tree`, and `Belt.Map` (an AVL tree, built from the same
comparator) as the standard to beat: the same operations on each, at 1,000, 10,000 and 100,000
keys (see `SortedMapSuite.res` for what they are, and `SortedMaps.res` for the implementations).
The run ends with a table of them side by side.

Then one thing only `BTree` has: how its node size affects editing.

Every benchmark passes its result to `Mitata.doNotOptimize`. This file is bundled together with
the code it measures (see ../vite.config.ts), so without that both Terser and the JIT could see
that a result is unused and delete the work that produced it.

Benchmark names include the implementation, the operation and the tree size, since the filter
argument (see `Runner.main`) matches on a benchmark's own name, not its group's.
*/

open ResBenchmarking
module BTree = ResBTree.BTree

let comparison = Comparison.make(
  ~implementations=SortedMaps.all->Array.map(implementation => {
    module M = unpack(implementation)
    M.name
  }),
)

SortedMapSuite.register(comparison, SortedMaps.all, ~sizes=[1_000, 10_000, 100_000])

/** Inserts then removes `n` random keys at each of a range of node sizes. */
let benchMaxNodeSizes = (n: int) => {
  let orders = () => {
    let random = SeededRandom.make(42.0)
    let insertOrder = SeededRandom.shuffledRange(random, n)
    (insertOrder, SeededRandom.shuffledRange(random, n))
  }

  Mitata.group(`maxNodeSize, inserting then removing n=${Int.toString(n)}`, () =>
    Mitata.summary(() =>
      [4, 16, 32, 64, 256]->Array.forEach(
        maxNodeSize =>
          Mitata.benchWithSetup(
            `BTree insert+remove maxNodeSize=${Int.toString(maxNodeSize)}`,
            () => {
              let (insertOrder, removeOrder) = orders()
              {
                measure: () => {
                  let current = ref(BTree.make(~id=SortedMapSuite.id, ~maxNodeSize))
                  for i in 0 to n - 1 {
                    let key = Array.getUnsafe(insertOrder, i)
                    current := BTree.set(current.contents, key, key)
                  }
                  for i in 0 to n - 1 {
                    current := BTree.remove(current.contents, Array.getUnsafe(removeOrder, i))
                  }
                  Mitata.doNotOptimize(current.contents)
                },
              }
            },
          )->ignore,
      )
    )
  )
}

benchMaxNodeSizes(100_000)

comparison->Comparison.print(await Runner.main())
