/***
A 32-bit string hash (a MurmurHash3-derived hash, adapted from the JavaScript reference at
https://github.com/bryc/code/blob/master/jshash/PRNGs.md, public domain), plus
helpers for building hashes of other values from it.

Belt has no string/structural hashing implementation of its own:
`Belt.Id.hashable(~hash, ~eq)` is a slot you plug your own `'a => int` function
into, not an implementation, so there's nothing to delegate to here.

One behavioral difference from the JavaScript reference: it ends with `>>> 0`,
producing an *unsigned* 32-bit result (always `>= 0`), whereas ReScript's `int`
is signed and there is no unsigned 32-bit integer type to convert to. Every
function here returns the signed interpretation of the exact same bits instead
(`hashString("")` is `-1421968373` here, where the JavaScript version returns
`2872998923`, i.e. `2872998923 - 2**32`). Results still agree bit-for-bit with the
JavaScript version; only the sign of values `>= 2**31` differs, which is irrelevant for
hashing's actual use (bucket/equality comparisons) but worth knowing when diffing
outputs against it directly.

None of these hashes are cryptographic.
*/

/**
The MurmurHash3 finalizer (avalanche mix). Exposed standalone so callers that need
a stream of hash-derived values (e.g. seeding a PRNG) can repeatedly mix an
evolving state without recomputing `hashString` from scratch.
*/
let murmurFinalize: int => int

/**
A 32-bit hash of a string. Fast, well-distributed mixing for hash tables, dedup keys, and the like.
*/
let hashString: string => int

/**
A 32-bit hash of an `int`, computed by hashing its decimal string representation.
Adequate for hash-table-style use; not a substitute for a real integer hash when raw
throughput on dense integer keys matters.
*/
let hashInt: int => int

/**
Combines two hash values into one, in a way that's sensitive to argument order
(`combine(a, b) != combine(b, a)` in general). For building a structural hash of a
compound value (e.g. a tuple or record) from its fields' individual hashes, one
field at a time.
*/
let combine: (int, int) => int
