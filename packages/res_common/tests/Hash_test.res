/***
Expected values below were computed by a JavaScript implementation of the
same hash (`xmur3a`/`murmurFinalize`), run in Node, to confirm this one agrees
bit-for-bit -- see `Hash.resi`'s
module comment for the one difference (signed vs. unsigned interpretation
of the same bits).
*/

open Vitest

describe("Hash.hashString", () => {
  test("matches the JavaScript implementation, value by value", t => {
    t->expect(Hash.hashString(""))->Expect.toBe(-1421968373)
    t->expect(Hash.hashString("a"))->Expect.toBe(-1287157080)
    t->expect(Hash.hashString("hello"))->Expect.toBe(1906870752)
    t->expect(Hash.hashString("hello world"))->Expect.toBe(1943396343)
    t
    ->expect(Hash.hashString("The quick brown fox jumps over the lazy dog"))
    ->Expect.toBe(1437045451)
    t->expect(Hash.hashString("42"))->Expect.toBe(1425518244)
  })

  test("is deterministic: the same input always hashes the same", t => {
    t->expect(Hash.hashString("determinism"))->Expect.toBe(Hash.hashString("determinism"))
  })

  test("different strings (usually) hash differently", t => {
    t->expect(Hash.hashString("abc") == Hash.hashString("abd"))->Expect.toBeFalsy
    t->expect(Hash.hashString("abc") == Hash.hashString("cba"))->Expect.toBeFalsy
  })

  test("is sensitive to string length even when a prefix repeats", t => {
    t->expect(Hash.hashString("a") == Hash.hashString("aa"))->Expect.toBeFalsy
  })
})

describe("Hash.murmurFinalize", () => {
  test("matches the JavaScript implementation, value by value", t => {
    t->expect(Hash.murmurFinalize(0))->Expect.toBe(0)
    t->expect(Hash.murmurFinalize(1))->Expect.toBe(1364076727)
    t->expect(Hash.murmurFinalize(-1))->Expect.toBe(-2114883783)
  })
})

describe("Hash.hashInt", () => {
  test("is deterministic and distinguishes distinct ints", t => {
    t->expect(Hash.hashInt(42))->Expect.toBe(Hash.hashInt(42))
    t->expect(Hash.hashInt(42) == Hash.hashInt(43))->Expect.toBeFalsy
  })

  test("agrees with hashString on the int's decimal representation", t => {
    t->expect(Hash.hashInt(42))->Expect.toBe(Hash.hashString("42"))
  })
})

describe("Hash.combine", () => {
  test("is deterministic", t => {
    t->expect(Hash.combine(1, 2))->Expect.toBe(Hash.combine(1, 2))
  })

  test("is sensitive to argument order", t => {
    t->expect(Hash.combine(1, 2) == Hash.combine(2, 1))->Expect.toBeFalsy
  })

  test("distinguishes different pairs", t => {
    t->expect(Hash.combine(1, 2) == Hash.combine(1, 3))->Expect.toBeFalsy
  })
})

describe("Hash: oracle-style distribution check", () => {
  test("hashing many distinct strings produces few collisions", t => {
    let random = TestSupport.Random.make(2024.0)
    let seen = Belt.MutableSet.Int.make()
    let collisions = ref(0)
    let count = 5000

    for i in 1 to count {
      let value = `key-${Int.toString(i)}-${Float.toString(TestSupport.Random.next(random))}`
      let h = Hash.hashString(value)
      if seen->Belt.MutableSet.Int.has(h) {
        collisions := collisions.contents + 1
      } else {
        seen->Belt.MutableSet.Int.add(h)
      }
    }

    // For a well-mixed 32-bit hash, 5000 distinct inputs should essentially never
    // collide (the birthday-paradox expectation is about 0.003 collisions). The
    // `< 5` bound leaves slack for an unlucky draw while still catching a
    // systematic clash (e.g. every input landing in a handful of buckets), which
    // would indicate the port broke the mixing somewhere.
    t->expect(collisions.contents < 5)->Expect.toBeTruthy
  })
})
