/***
A Lehmer/Park-Miller LCG PRNG, seeded so that every run of a benchmark measures the same inputs:
two runs are only comparable if the keys they insert and look up are identical.

The multiply-then-mod runs in `float` (a real JS double, exact up to 2**53): `state * 48271` can
exceed `int`'s 32-bit range, and ReScript's `int` arithmetic would silently wrap it before the
`mod` is applied.
*/

type t = ref<float>

/** A generator starting from `seed`, which must be in `[1, 2^31 - 2]`. */
let make = (seed: float): t => ref(seed)

let modFloat = (a: float, m: float): float => a -. m *. Int.toFloat(Float.toInt(a /. m))

/** The next pseudo-random value, in `[1, 2^31 - 2]`. */
let next = (state: t): float => {
  state := modFloat(state.contents *. 48271.0, 2147483647.0)
  state.contents
}

/** A pseudo-random integer in `[0, bound)`. */
let nextInt = (state: t, bound: int): int => Float.toInt(modFloat(next(state), Int.toFloat(bound)))

/** A Fisher-Yates shuffle of `[0, n)`. */
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
