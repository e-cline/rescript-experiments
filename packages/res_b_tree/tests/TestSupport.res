/***
Shared support for the test files in this package. Not itself a test (no `_test` suffix, so Vitest's
`test.include` never picks it up), just ordinary helper code they all use.
*/

/**
A comparator for plain `int` keys, via `Belt.Id.MakeComparable` --
every test needs one of these to call `BTree.make`/`fromArray`. `a - b` can
overflow for extreme values; fine for the small keys the tests use.
*/
module IntCmp = Belt.Id.MakeComparable({
  type t = int
  let cmp = (a: int, b: int) => a - b
})

let intId: Belt.Id.comparable<int, IntCmp.identity> = module(IntCmp)

/**
A Lehmer/Park-Miller LCG PRNG, seeded for reproducibility -- a flaky,
hard-to-reproduce test failure is worse than a fixed seed that always
exercises the same (still effectively arbitrary) sequence.

The multiply-then-mod runs in `float` (a real JS double, exact up to 2**53):
`state * 48271` can exceed `int`'s 32-bit range, and ReScript's `int`
arithmetic would silently wrap it before the `mod` is applied.
*/
module Random = {
  type t = ref<float>

  let make = (seed: float): t => ref(seed)

  let modFloat = (a: float, m: float): float => a -. m *. Int.toFloat(Float.toInt(a /. m))

  /**
  The next pseudo-random value, in `[1, 2^31 - 2]` for any seed in that range
  (`0` would be a fixed point).
  */
  let next = (state: t): float => {
    state := modFloat(state.contents *. 48271.0, 2147483647.0)
    state.contents
  }

  /**
  A pseudo-random integer in [0, bound).
  */
  let nextInt = (state: t, bound: int): int =>
    Float.toInt(modFloat(next(state), Int.toFloat(bound)))

  /**
  A Fisher-Yates shuffle of `[0, n)`.
  */
  let shuffledRange = (state: t, n: int): array<int> => {
    let array = Belt.Array.makeBy(n, i => i)
    for i in n - 1 downto 1 {
      let j = nextInt(state, i + 1)
      let temp = Array.getUnsafe(array, i)
      array[i] = Array.getUnsafe(array, j)
      array[j] = temp
    }
    array
  }
}
