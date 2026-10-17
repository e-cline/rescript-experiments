# @e-cline/res_common

ReScript utilities that don't already have a direct `Belt` equivalent -- array utilities and an
`ImmutableArray`, debug-only assertions, hashing, and a lazy sequence type -- plus `Env.res`,
`isDev`/`isProd` bindings to [`@e-cline/js_env`](https://github.com/e-cline/js_env)'s dev/prod
constants (formerly its own package, `res_env`, until it shrank to a single tiny wrapper module and
moved in here).

## Installing

Needs ReScript 12.

```bash
npm install @e-cline/res_common rescript @rescript/runtime
```

Add `"@e-cline/res_common"` to the `dependencies` in your `rescript.json`. The modules are under the
`ResCommon` namespace (`ResCommon.Hash.hashString`), and your project's `rescript build` compiles
them along with your own code.

## Layout

Every module here is a top-level `src/*.res` + `.resi` pair (no `internal/` subdirectory -- unlike
`res_trees`, nothing here is deep enough to need one), each independent of the others except where
noted:

- **`Env.res`** -- `isDev`/`isProd`, bound to `@e-cline/js_env`'s `IS_DEV`/`IS_PROD` constants via a
  `@module` external, so a bundler's export-condition resolution (and then its dead-code
  elimination) applies to them normally. See "Debug-only assertions" below for why this can't be a
  normal cross-package ReScript dependency.
- **`Debug.res`** -- `assert_`/`fail` (always-on) and `debugAssert` (a no-op unless `Env.isDev`
  resolves its "development" condition). See "Debug-only assertions" below.
- **`Arrays.res`** -- free functions over plain `array<'a>`: `chunk`, `zip`/`zipWith`, `partition`,
  `groupBy`, `uniqueBy`, `flatten`, `bisectLeft`/`bisectRight`, and the immutable positional-splice
  helpers (`insertAt`/`removeAt`/`replaceAt`) `ImmutableArray.res` builds on.
- **`ImmutableArray.res`** -- a persistent array wrapper, `ImmutableArray.t<'a>`, built on `Arrays`.
  See "ImmutableArray" below.
- **`Hash.res`** -- `hashString`/`hashInt`/`combine`, a MurmurHash3-derived 32-bit string hash, plus
  helpers for hashing other values with it.
- **`Sequence.res`** -- a generic lazy sequence, `Sequence.t<'a>`, following OCaml's `Seq` module
  idiom. See "Sequence" below.
- **`tests/TestSupport.res`** (no `_test` suffix, so it isn't itself picked up as a test file) --
  shared test fixtures: a seeded Lehmer/Park-Miller PRNG, duplicated from
  `res_trees/tests/TestSupport.res` rather than imported from it -- this is test-only
  infrastructure, not something either package's real API should depend on the other for.

Like most ReScript libraries, this package has no `exports` map in its `package.json`: it ships its
`.res`/`.resi` source, and the consuming project's compiler builds it, so the compiled files have to
be importable from wherever that project's `rescript.json` puts them.

## Belt usage

Following `res_trees`'s established convention: reach for Belt directly wherever it already has a
direct equivalent, and only hand-write something where it doesn't.

- **`Arrays`** exists specifically because Belt has no chunk/zip/partition/groupBy/unique/flatten,
  and no immutable positional-splice helpers either (the same gap
  `res_trees/src/btree/internal/ArrayOps.res` filled privately for its own use -- see "Why `Arrays`
  doesn't just import `res_trees`'s `ArrayOps`" below). Where Belt does have a direct equivalent,
  this uses it instead of reinventing it: `zip`/ `zipWith` delegate to
  `Belt.Array.zip`/`Belt.Array.zipBy`, and `groupBy`/`uniqueBy` are built on
  `Belt.Map.String`/`Belt.MutableSet.String` rather than a hand-rolled hash table.
- **Belt has no string/structural hashing implementation and no lazy sequence type**
  (`Belt.Id.hashable(~hash, ~eq)` is a _slot_ you plug a hash function into, not an
  implementation) -- confirmed by checking `@rescript/runtime`'s actual module list before writing
  `Hash`/`Sequence`, rather than assuming. Each of those fills a genuine gap, not a re-wrap.
- **`Hash.res` binds `Math.imul` directly** (`@val external imul: (int, int) => int = "Math.imul"`),
  since the murmur3 algorithm specifically depends on 32-bit-truncated multiplication and
  `@rescript/runtime` doesn't expose that particular operation, unlike the bitwise ops it does cover
  (`Int.bitwiseXor`/`Int.bitwiseOr`/`Int.shiftLeft`/`Int.shiftRightUnsigned`, all used directly).

### Why `Arrays` doesn't just import `res_trees`'s `ArrayOps`

`res_trees/src/btree/internal/ArrayOps.res` already has benchmarked, working versions of
`insertAt`/`removeAt`/ `replaceAt`. `Arrays.res` here duplicates that shape (and the same
`Belt.Array.makeUninitializedUnsafe`

- hand-written-loop technique, for the same benchmarked reason -- see `ArrayOps.res`'s own header
  comment) rather than making `res_common` a dependency of `res_trees` (or vice versa) to share it.
  `res_trees` already shipped, was already benchmarked as a whole, and its `ArrayOps` is
  `internal/` -- not exposed, not meant to be a public dependency target -- so reaching into it from
  a new package would mean either exposing it publicly (churn to an already-finished package, for a
  benefit that amounts to a few dozen lines) or depending on `res_trees` as a whole just to get its
  array helpers. Duplicating a small, self-contained, already-correct algorithm is the smaller
  footprint here.

## Debug-only assertions

`Debug.assert_`/`Debug.fail` always throw when their condition fails; `Debug.debugAssert` does the
same _unless_ `Env.isDev` resolves to `false` (a production build), in which case it's a no-op. Two
design choices worth knowing:

- **`message` is always a thunk** (`unit => string`), not a `string | (() => string)` union --
  ReScript's optional labeled arguments don't overload cleanly over a union the way a TS parameter
  type can, so there's one signature. The thunk still means an expensive message (e.g. one that
  stringifies a large value) is never built when the assertion holds.
- **Failures throw a plain `JsError.t`, not a dedicated `AssertionError` class.** A hand-rolled
  ReScript `exception` doesn't compile to a real JS `Error` (it carries a payload, not a `.message`
  property), so it doesn't work with anything that expects a normal thrown error -- including
  Vitest's own `toThrow(~message)` matcher, which is how `Debug_test.res` verifies failure messages.
  Nothing in this package needs to distinguish "an assertion failed" from any other error by
  exception identity, so there's no real cost to not having a dedicated class.

TS's `checkExhaustive`/`type_guards.ts`/`common_guards.ts` weren't ported: `checkExhaustive` exists
to paper over TS's weaker exhaustiveness checking (a `never`-typed parameter flags a stale switch at
the _call site_); ReScript's own `switch` over a variant already gives real, compiler-enforced
exhaustiveness warnings, so a runtime helper adds nothing. The type-guard modules exist to recover
static typing from `unknown`/runtime values in a structurally-typed language with no real sum types;
ReScript's `option`/variants make most of that unnecessary at the type level.

See `Env.res`'s own header comment for how the dev/prod flag itself is resolved -- notably, _not_
through ReScript's own cross-package module resolution to `@e-cline/js_env` (which isn't even a
ReScript package), since the ReScript compiler (unlike a JS bundler) has to pick one concrete module
per import at compile time. `Env.res` instead binds directly to the plain string package specifier
with `@module("@e-cline/js_env") external isDev: bool = "IS_DEV"`, an ordinary JS import that a
bundler's export-condition resolution (and then its dead-code elimination) still applies to
normally -- confirmed end-to-end by [`examples/res_tree_shaking`](../../examples/res_tree_shaking),
which builds a small app through this module and asserts the `isDev`-only branch is actually gone
from the production bundle. `Env.jsEnv` exposes `@e-cline/js_env`'s `env` (`'dev' | 'prod'`) as a
`Development | Production` variant for use with `switch`; its cases are backed by those strings
(`@as("dev")`/`@as("prod")`), so it's bound straight to `env` with no runtime mapping, and the same
example confirms a `switch` on it tree-shakes too.

## ImmutableArray

`ImmutableArray.t<'a>` is a persistent array: every operation returns a new `t`, never touching the
one it was called on. It's kept deliberately simple: "a plain array with a type that guarantees you
can't mutate it by accident," built on `Arrays`' helpers, not a tree-backed structure with real
structural sharing on every edit. `t<'a>` is opaque (`ImmutableArray.resi`), and
`fromArray`/`toArray` always copy -- the one invariant this type exists to hold is that nothing
outside this module can mutate the array a `t` wraps out from under it, whether by keeping a
reference to what was passed in or by mutating what came out.

If an access pattern actually needs real structural sharing on large collections (most of a big
array unchanged across edits, e.g. an undo history over a large dataset), that's what `res_trees`'s
`BTree` is for -- `ImmutableArray` intentionally doesn't try to be that.

## Sequence

`Sequence.t<'a>` is a generic lazy sequence, following OCaml's own `Seq` module (and Melange's copy
of it): neither Belt nor `@rescript/core` has anything like it. A sequence is a thunk that, when
forced, produces either "nothing left" (`Nil`) or "one value, plus a thunk for the rest" (`Cons`) --
laziness all the way down, not just at the front, which is what lets `iterate`/`repeat` represent
genuinely infinite sequences: nothing forces more of the sequence than a consumer (e.g. `take`)
actually asks for.

`node`/`t` are deliberately **not** opaque, unlike this package's other stateful types. The entire
value of a lazy sequence -- same as OCaml's public `Seq` -- is being able to write a new combinator
by pattern-matching `t()` directly, without this module anticipating it; there's no invariant here a
caller could violate by constructing a `Cons`/`Nil` by hand; any well-formed `unit => node<'a>` is a
valid sequence.

Getting the laziness actually right took one real fix, caught by a test that counts how many times a
generator function is called (`Sequence_test.res`'s "genuine laziness" tests): the first version of
`iterate(seed, f)` was `Cons(value, go(f(value)))`, which calls `f(value)` as soon as the _current_
element is forced -- one element earlier than anything had actually asked for, since `go(f(value))`
needs `f(value)`'s value to even construct the next thunk (function application is strict). Wrapping
it in another thunk (`Cons(value, () => go(f(value))())`) defers that call until the _next_ element
is actually forced, which is the point where `map`/`filter`/`take`/etc.'s recursive calls
(`map(rest, f)`, not `map(rest(), f)`) already deferred correctly -- `iterate` was the one place a
plain value (not an already-lazy `t<'a>`) needed the same treatment spelled out explicitly.

## Testing

Every test is written directly in ReScript with
[`rescript-vitest`](https://github.com/cometkim/rescript-vitest), following `res_trees`'s
conventions: ordinary unit tests plus edge cases (empty/single-element inputs, out-of-bounds access,
custom comparators), and where an independent reference exists, an oracle-style stress test that
cross-checks a long randomized sequence of operations against it (a plain mutable array for
`ImmutableArray`, `Array.filter`/`map`/`slice` for `Sequence`) rather than hand-computed expected
values. `Hash_test.res` additionally checks several concrete hash values against ones computed by a
JavaScript implementation of the same hash, run in Node, to confirm the two agree bit-for-bit
(modulo the one cosmetic signed/unsigned difference `Hash.resi`'s module comment explains).
