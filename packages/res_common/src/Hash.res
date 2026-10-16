// See `Hash.resi` for the public-facing description and the one behavioral
// difference from the JavaScript reference: a signed result.
//
// The JavaScript reference relies on `Math.imul`/`>>> 0` for 32-bit-truncated
// multiplication and unsigned shifts. `Int.bitwiseXor`/`Int.bitwiseOr`/
// `Int.shiftLeft`/`Int.shiftRightUnsigned` are the direct equivalents of JS's
// `^`, `|`, `<<`, and `>>>`. Multiplication is the exception: ReScript compiles
// `a * b` on `int`s to plain JS `a * b | 0`, i.e. a double-precision multiply
// that is truncated to 32 bits *afterwards*. That is only exact while the
// product stays below 2**53; two full-width 32-bit operands (as in murmur's
// mixing steps) can exceed it and lose their low bits before the truncation,
// giving a different answer than a true 32-bit multiply. So the multiplications
// here go through `Math.imul` instead, bound directly below (the runtime's own
// `Math.Int.imul` is the same external).
@val external imul: (int, int) => int = "Math.imul"

// The algorithm's mixing constants, as the reference gives them (`2166136261`,
// `3432918353`, ...; the trailing comments below repeat each one as written).
// Several exceed `int`'s 32-bit signed range (2147483647) as written, so each
// is rewritten as its 32-bit signed two's-complement equivalent (`n - 2**32`):
// the same bit pattern, in the range ReScript's `int` literals accept.
// `imul`/the bitwise ops only ever look at the bits, so the rewrite has no
// effect on the algorithm itself.
let seedConstant = -2128831035 // 2166136261
let mixConstant1 = -862048943 // 3432918353
let mixConstant2 = 461845907 // already in range
let mixConstant3 = -430675100 // 3864292196
let finalizeConstant1 = -2048144789 // 2246822507
let finalizeConstant2 = -1028477387 // 3266489909

let murmurFinalize = (h: int): int => {
  let h = Int.bitwiseXor(h, Int.shiftRightUnsigned(h, 16))
  let h = imul(h, finalizeConstant1)
  let h = Int.bitwiseXor(h, Int.shiftRightUnsigned(h, 13))
  let h = imul(h, finalizeConstant2)
  let h = Int.bitwiseXor(h, Int.shiftRightUnsigned(h, 16))
  h
}

let hashString = (str: string): int => {
  let h = ref(seedConstant)
  for i in 0 to String.length(str) - 1 {
    let k0 = imul(String.charCodeAtUnsafe(str, i), mixConstant1)
    let k1 = Int.bitwiseOr(Int.shiftLeft(k0, 15), Int.shiftRightUnsigned(k0, 17))
    h := Int.bitwiseXor(h.contents, imul(k1, mixConstant2))
    h := Int.bitwiseOr(Int.shiftLeft(h.contents, 13), Int.shiftRightUnsigned(h.contents, 19))
    h := imul(h.contents, 5) + mixConstant3
  }
  h := Int.bitwiseXor(h.contents, String.length(str))
  murmurFinalize(h.contents)
}

let hashInt = (n: int): int => hashString(Int.toString(n))

let combine = (a: int, b: int): int => murmurFinalize(Int.bitwiseXor(imul(a, 5), b))
