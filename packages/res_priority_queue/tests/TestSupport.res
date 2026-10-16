/***
Shared support for the test files in this package. Not itself a test (no `_test` suffix, so Vitest's
`test.include` never picks it up), just ordinary helper code they all use.
*/

/**
A comparator for plain `int` keys, via `Belt.Id.MakeComparable` -- the
`Belt.Id.comparable<int, _>` both `MutablePriorityQueue` and `PriorityQueue`
tests order their elements by. `a - b` can overflow for extreme values; fine for
the small keys the tests use.
*/
module IntCmp = Belt.Id.MakeComparable({
  type t = int
  let cmp = (a: int, b: int) => a - b
})

let intId: Belt.Id.comparable<int, IntCmp.identity> = module(IntCmp)

/**
A Lehmer/Park-Miller LCG PRNG, seeded for reproducibility -- a flaky,
hard-to-reproduce test failure is worse than a fixed seed that always
exercises the same (still effectively arbitrary) sequence. The same as
`res_common/tests/TestSupport.res`'s `Random` module, trimmed to what the
tests here use -- duplicated rather than shared across packages, since this is
test-only infrastructure, not something either package's public API should
depend on the other for.

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
}
