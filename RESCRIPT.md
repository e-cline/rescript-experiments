# Authoring packages in ReScript: findings

This is a writeup of a hands-on exploration into authoring packages in
[ReScript](https://rescript-lang.org/) instead of TypeScript in this workspace, integrated with the
Vite+ toolchain. Everything described below was actually built and run in this repo -- see the "Demo
packages" section for what to look at and how to reproduce the results yourself.

> **Some of this exploration has since been removed.** The TypeScript-interop chain -- `res_math` (a
> ReScript package with a genType-emitted `.d.ts`), `ts_shapes` (a TypeScript package), `res_shapes`
> (ReScript consuming both, through `ts2ocaml`-generated bindings) and `examples/res-consumer`
> (TypeScript consuming them) -- was deleted before this repository was published, and its code
> isn't included here. The findings that depended on it are kept below as a record and marked
> _(removed)_. Everything not marked that way describes what's in the repository today.

**Bottom line: it works, end to end, including the harder directions (cross-ReScript-package deps,
consuming a TypeScript package's types from ReScript, React + CSS Modules + a third-party ReScript
library, and writing tests directly in ReScript against Vitest), and none of it needed a bundler
plugin.** The rough edges are real but narrow, and each one has a concrete, working fix documented
below.

## How it plugs into Vite+

The integration point turned out to be simpler than expected, because ReScript's own compiler
already does most of the work:

- `rescript build` (configured via `rescript.json`, with `"in-source": true` and
  `"suffix": ".res.jsx"`) compiles `.res`/`.resi` source to ESM `.res.jsx` files, colocated with the
  source. The root `rescript.json` sets `"jsx": {"version": 4, "preserve": true}`, so JSX in `.res`
  files (`@jsx.component` components) stays JSX in the output instead of being lowered to
  `JsxRuntime.jsx` calls -- which is why the suffix is `.res.jsx` rather than `.res.mjs`: Vite (oxc)
  and tsdown only transform JSX in `.jsx`/`.tsx` files, and a `.mjs` containing `<div>` is a syntax
  error to them. Vite and Vitest resolve these like any other `.jsx` file -- **no bundler plugin is
  needed at all** for the compiled output itself. (Node can't run `.jsx` directly; use `tsx`, as
  `res_pretty_print`'s `demo` task does.)
- [genType](https://rescript-lang.org/docs/manual/typescript-integration) (built into the compiler
  since ReScript 10.1, configured via `rescript.json`'s `gentypeconfig`) emits a `*.gen.tsx` file
  for every module with a `@genType`-annotated export. That file is itself ordinary TypeScript -- it
  re-exports the compiled `.res.jsx` runtime under real TS types. Because it's ordinary TypeScript,
  **`vp pack`'s `tsgo`-driven `dts` pass and `tsc --noEmit` handle it like any other `.tsx` entry**,
  no special-casing required beyond `"allowJs": true` (see below).

That means the whole integration is: run `rescript build` before anything that reads `src/`, and
write `src/index.ts` to re-export from the `.gen.tsx` file(s) you care about, exactly as every other
package here writes `src/index.ts`. See `vite.config.base.ts`'s `makeRescriptLibConfig` -- it's
`makeLibConfig` plus a `dependsOn` on the root-level `res` task (`rescript build`, see "One root
`res` task" below) for `build`/`test`/`typecheck`. A package using it looks identical to a
TypeScript-authored one from the outside: same `pack.entry: 'src/index.ts'`, same `dist/*.d.ts` +
`dist/*.js` shape, same `package.json` `exports` map.

Two small, unavoidable additions in a ReScript package's own `tsconfig.json`:

- `"allowJs": true` -- `.gen.tsx` imports the compiled `.res.jsx` sibling, which has no `.d.ts` of
  its own; without `allowJs`, TypeScript refuses to resolve that import at all (`TS7016`/`TS2307`,
  depending on version). This is harmless: the accurate types are the ones genType writes in the
  same file, not the untyped import.
- `"jsx": "preserve"` (or `"react-jsx"` for a component package) -- genType always names its output
  `*.gen.tsx`, even with zero JSX in it, and TypeScript requires `jsx` to be set for any `.tsx` file
  regardless of content.

### One root `res` task, not one per package

ReScript is compiled by a single task, `res`, declared in the **root** `vite.config.ts` (it runs
`rescript build` from the repo root, which follows the root `rescript.json`'s `dependencies` to
build every `packages/*` package). Packages don't declare their own `res` task; their
`build`/`test`/`typecheck` depend on it as `'@e-cline/res-experiments#res'` (exported as
`rootResTask` from `vite.config.base.ts`). Run it by itself with `vp run -w res`.

This is deliberate. `rescript build` compiles a package's ReScript _dependencies_ (`@rescript/core`,
`rescript-vitest`, ...) in place, into `lib/` inside the dependency's directory under
`node_modules/.pnpm`, and pnpm gives every package that depends on the same version the _same_
directory. With a `res` task per package, `vp run -r build` ran several of those compiles in
parallel, and two of them writing the same dependency's `lib/` at once intermittently failed with
`Corrupted compiled interface` (seen on `@rescript/core`'s `core__ArrayBuffer.cmi`). One
`rescript build` at the root compiles every shared dependency once, in dependency order, in one
process, so the race cannot happen -- including for ReScript dependencies added later. The trade-off
is that ReScript caching is all-or-nothing in Vite+ (any package's `.res` change re-runs the root
task, though ReScript's own incremental build keeps that fast).

`res:watch` (`rescript build -w`, also declared at the root; run with `vp run -w res:watch`) is
provided for local dev but deliberately **not** wired into any `dependsOn` -- a `-w` process never
exits, and `dependsOn` means "finish before starting," so depending on it would deadlock the task
graph. It watches the whole workspace. Run it in its own terminal alongside `vp run test:watch` /
`vp run build:watch`; Vite/Vitest already watch the whole package directory, so they pick up the
rewritten `.res.jsx`/ `.gen.tsx` files with no extra wiring. This is the one place where genuine
"live reload on `.res` edit" isn't a single command yet -- see Gaps below.

## Testing directly in ReScript

Every ReScript package here has its tests written directly in ReScript -- for example
`packages/res_trees/tests/btree/BTree_test.res` -- using
[`rescript-vitest`](https://github.com/cometkim/rescript-vitest) (`cometkim/rescript-vitest`,
published to npm as plain `rescript-vitest`). It worked essentially out of the box:
`describe`/`test`/`expect` are thin bindings to Vitest's real runtime, so failures come back as
genuine Vitest `AssertionError`s with real expected/received diffs, not something bolted on.

Two things needed fixing to make it fit this repo's conventions, both now in `vite.config.base.ts`'s
`makeRescriptLibConfig`:

- **Vitest's default `test.include` doesn't match ReScript's compiled test output.**
  `rescript.json`'s `"suffix": ".res.jsx"` (used everywhere here: JSX preserve mode needs a
  JSX-aware extension, and it stays visually distinct from hand-written JS) means a ReScript test
  file compiles to e.g. `BTree_test.res.jsx`, not `BTree_test.mjs` -- Vitest's default
  `**/*.{test,spec}.?(c|m)[jt]s?(x)` glob requires the extension to follow `.test`/`.spec` directly,
  with nothing in between. Fixed with a second `include` pattern, `**/*_{test,spec}.res.jsx`.
- **`rescript build` mirrors compiled test files into its own `lib/bs/` build cache**, and the new
  include pattern above matches that mirrored copy too, so every ReScript test would otherwise run
  _twice_. Fixed by excluding `lib/**` in `test.exclude` -- `rescript-vitest`'s own repository needs
  the identical exclusion, for the identical reason.

Each package's `tests/` is a source directory of its own in `rescript.json`, marked `"type": "dev"`,
and `rescript-vitest` is listed under `dev-dependencies` rather than `dependencies`. That keeps the
tests out of what a project depending on the package compiles, so it doesn't need `rescript-vitest`
either. Within this workspace nothing changes: the root `rescript build` still compiles every
package's tests.

The naming convention itself surfaced a real ReScript gotcha, not a testing-library one: **a test
file named after the module it tests, using a literal `.test.` infix, silently collides with that
module.** ReScript derives a module name from the filename by capitalizing only the first letter, so
a `point.test.res` testing a `Point.res` becomes module `Point.test` -- and ReScript treats the dot
as nesting a submodule _under_ `Point`, colliding with the real `Point` module in the same
directory. The resulting compiler error ("The module or file Point can't be found," pointing at the
reference to `Point` inside the test) gives no hint that the test file's own name is the cause. The
fix is the naming convention used here instead: `<Module>_test.res` (`Point_test.res`, not
`point.test.res`) -- an underscore can't collide with capitalization the way a dot can. This is
specific to a test file that would otherwise share its exact name with the module it tests;
`rescript-vitest`'s own example tests (`basic.test.res`, testing a suite called "basic" rather than
a module called `Basic`) never hit it, which is presumably why it isn't documented anywhere
upstream.

`res_react_ui`'s test deliberately stays in TypeScript (`greeting.test.tsx`, using
`react-dom/server`): rendering a React component and asserting on markup is a React Testing
Library-shaped problem, and `rescript-vitest` only binds Vitest's assertion API, not a rendering
library -- there's no ReScript binding for one in this workspace. That would be the natural next
piece to build (as its own small `packages` companion package, the same way this workspace would
build any other missing binding) if ReScript-authored UI-component tests become a priority; it
wasn't attempted here.

## Demo packages

What there is to look at, and what each one validates:

| Package                                                      | Validates                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`packages/res_common`](packages/res_common)                 | Utilities with no `Belt` equivalent: array utilities + an `ImmutableArray`, debug-only assertions (via `Env.res`; see gap #13), hashing (a MurmurHash3-derived string hash, verified bit-for-bit against a JavaScript implementation), and a lazy `Sequence` type following OCaml's `Seq` module idiom. `Env.res` (`isDev`/`isProd`, bound to `@e-cline/js_env`'s constants) started life as its own package, `res_env`, until it shrank to one tiny wrapper module and moved in here -- see gap #13 for the mechanism and [`examples/res_tree_shaking`](examples/res_tree_shaking), which builds a small app through it and asserts the `isDev`-only branch is actually gone from the production bundle. Tested directly in ReScript: unit tests plus edge cases throughout, oracle stress tests against a plain mutable array/`Array` combinators where an independent reference exists, and (for `Sequence`) tests that count generator-function calls to verify laziness is real, not just apparently-correct output -- which caught a genuine one-step-too-eager bug in `iterate` (see its own README section). |
| [`packages/res_priority_queue`](packages/res_priority_queue) | The priority queues that used to live in `res_common`, split out into their own package: a mutable one (an array-backed binary heap) and an immutable one (a leftist heap, following the standard OCaml/Melange approach). Both identify priority via `Belt.Id.comparable`, matching `res_trees`'s convention. A small example of one ReScript package depending on another: it lists `@e-cline/res_common` in its `rescript.json` `dependencies` and calls `ResCommon.Debug.fail` for its `*Exn` failures. Tested directly in ReScript: unit tests plus edge cases, and an oracle stress test of each queue against a sorted array.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| [`packages/res_trees`](packages/res_trees)                   | A ReScript package with **no TypeScript surface at all** (no genType, no `src/index.ts`) -- three persistent sorted maps, each in its own `src/` subdirectory with mutable + immutable variants and structural-sharing-aware diffing: a B+tree (`src/btree/`), an AVL tree (`src/avl/`) and a chunked AVL tree (`src/chunk/`). Meant to be consumed only from other ReScript code. The B+tree is organized as a small internal-module hierarchy (`internal/Node`/`Insert`/`Delete`/`Diff`, each with its own `.resi`) behind an opaque public `BTree.t`/`MutableBTree.t`; identifies keys via `Belt.Id.comparable` (like `Belt.Set`/`Belt.Map`) rather than a bare comparator function. Tested directly in ReScript: unit tests, a structural-invariant checker run after every mutation in two large oracle stress tests against `Belt.Map.Int` (a full insert-then-remove sweep, and a long randomized interleaving of inserts/overwrites/removals). The AVL and chunked trees follow the same layout, and all three run through one shared conformance suite.                                                     |
| [`packages/res_signals`](packages/res_signals)               | Reactive signals (atoms, computeds, effects with a pluggable scheduler) with diff-driven history. A ReScript package with no TypeScript surface, tested in ReScript including a randomized fuzz test.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| [`packages/res_signal_maps`](packages/res_signal_maps)       | A sorted, signal-backed map whose derived views update incrementally -- one ReScript package built on two others (`res_trees` and `res_signals`).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| [`packages/res_server`](packages/res_server)                 | A small HTTP server framework on the Web-standard `Request`/`Response` APIs, bound through the experimental `@rescript/webapi` and run on Node by Hono -- ReScript bindings to third-party JS packages, used from another ReScript package.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| [`examples/res_http_server`](examples/res_http_server)       | An HTTP server built with `res_server`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| [`examples/res_react_ui`](examples/res_react_ui)             | `@rescript/react` (JSX authoring), CSS Modules imported from `.res`, and a third-party ReScript library from npm (`rescript-webapi`).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| [`examples/res_react_app`](examples/res_react_app)           | A plain Vite React app importing `res_react_ui`'s component, run in both dev server and production build (verified rendering in-browser: correct text, correct third-party-library-computed value, correct CSS).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| [`examples/res_tree_shaking`](examples/res_tree_shaking)     | A small app built through `res_common`'s `Env`, asserting that an `isDev`-only branch is gone from the production bundle (see gap #13).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| [`tools/ppx/pretty_print`](tools/ppx/pretty_print)           | A ReScript PPX written in OCaml, built with dune from an opam switch local to its directory, that derives pretty-printers for types; [`examples/res_pretty_print`](examples/res_pretty_print) uses it.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| [`tools/benchmarking`](tools/benchmarking)                   | ReScript bindings to mitata and a seeded PRNG, shared by the `benchmarks/` package next to `res_trees`, `res_signals` and `res_signal_maps`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |

Reproduce any of it by following [CONTRIBUTING.md](CONTRIBUTING.md)'s setup (Node, pnpm and opam,
then `pnpm install`), then `pnpm run build` and `pnpm run test` (or run a single package's tasks
with `pnpm --filter <package> exec vp run <task>`).

## Requirement-by-requirement

- **ReScript type-checking/`.d.ts` emission/type-stripping integrated with Vite+ builds and tests**:
  done, no plugin, see above.
- **A ReScript package exports a `.d.ts` other packages can consume**: done -- `res_math`'s
  `dist/index.d.ts` was a completely ordinary TypeScript declaration file _(removed)_.
  `examples/res_react_ui` still does the same for a React component.
- **A ReScript package imports another package that exports TS types (`.d.ts`)**: done, via
  `ts2ocaml`, with caveats (see Gaps) _(removed)_.
- **Build + test ReScript packages with Vite+**: done (every package under `packages/`, and
  `examples/res_react_ui`).
- **Write tests directly in ReScript, ideally with Vitest**: done, via `rescript-vitest` -- see
  "Testing directly in ReScript" above.
- **Bundle a ReScript package so its types are consumable by both TS and ReScript consumers**: done
  -- `res_math` was consumed by `res_shapes` (ReScript) and by `examples/res-consumer` (TS)
  simultaneously _(removed)_.
- **Import/depend on another ReScript package and consume its types**: done (`res_priority_queue` →
  `res_common`, and `res_signal_maps` → `res_trees` and `res_signals`). The removed `res_shapes` →
  `res_math` chain also carried the types all the way through genType to a downstream TS consumer.
- **Import/depend on a TS package and convert its `.d.ts` to ReScript types, ideally
  automatically**: done, automatically, via `ts2ocaml` -- see Gaps for what "automatically" actually
  took _(removed)_.
- **ReScript's custom React authoring + CSS/styling**: done (`res_react_ui`), verified rendering
  correctly in an actual browser.
- **External/third-party OSS ReScript libraries**: done (`rescript-webapi` in `res_react_ui`).
- **VSCode integration in a monorepo-like setup**: addressed at the config level (see below); not
  independently verified inside an actual running VSCode instance in this environment.
- **Shared build tooling encapsulating the setup, like `makeLibConfig`**: done --
  `makeRescriptLibConfig` in `vite.config.base.ts`.
- **Follow ReScript's own
  [monorepo setup guide](https://rescript-lang.org/docs/manual/build-monorepo-setup)**: done -- a
  root [`rescript.json`](rescript.json) lists every `packages/*` ReScript package by name in its own
  `dependencies` array, letting a single `rescript build`/`rescript clean`/ `rescript format` from
  the repo root operate on the whole tree at once, with each ReScript package also added as a
  `workspace:*` `devDependency` of the root `package.json` (see gap #17) so pnpm actually symlinks
  them into the root's `node_modules` for Rewatch to resolve. The Vite+ pipeline builds through it
  too -- the root `vite.config.ts`'s single `res` task runs `rescript build` from here, and every
  package's `build`/`test`/`typecheck` depends on it (see "One root `res` task" above for why it
  replaced per-package `res` tasks).

## Gaps and rough edges (the "major issues" worth knowing about)

None of these blocked anything -- each has a working fix already applied in the demo packages -- but
none of them are things you'd guess from the official docs, so they're worth calling out explicitly:

1. _(removed)_ **genType's cross-package import path is wrong.** When a `.res` module in one package
   uses a `@genType`-annotated type from _another_ workspace package (e.g. `res_shapes`'s
   `Shape.res` using `res_math`'s `Point.t`), genType emits an import in the generated `.gen.tsx`
   that doesn't resolve -- observed both a naively-relative `./Point.gen` and a
   package-plus-source-path `@e-cline/res_math/src/Point.gen` (neither exists; the dependency only
   publishes `dist/*`). Neither
   [the TypeScript integration docs](https://rescript-lang.org/docs/manual/typescript-integration)
   nor the [monorepo setup guide](https://rescript-lang.org/docs/manual/build-monorepo-setup)
   mention this, and there's no `gentypeconfig` option for it. It was first fixed with a post-build
   script that rewrote the broken import to the real, resolvable package subpath
   (`@e-cline/res_math/Point.gen`), then with a hand-written `Point.gen.ts` shim in `res_shapes` for
   the broken path to resolve to; both went with the packages that needed them. It's a known
   upstream bug:
   [rescript-lang/rescript#8375](https://github.com/rescript-lang/rescript/issues/8375).
2. _(removed)_ **`ts2ocaml`'s generated ReScript "stdlib helper" doesn't match current
   `@rescript/core`.** `ts2ocaml res --create-stdlib` generates `Ts2ocaml.res`, which every
   generated binding file needs (`open Ts2ocaml`). As shipped (`@ocsigen/ts2ocaml@2.0.0-beta.3`), it
   references `BigInt.t`, a type `@rescript/core` removed in its 1.x line (current is 1.6.1) in
   favor of the builtin `bigint` primitive. Compiling fails with "This type constructor, `BigInt.t`,
   can't be found" until every occurrence is replaced with `bigint` by hand -- a one-time fix per
   generated `Ts2ocaml.res`, not per binding file. `@rescript/core@1.0.0` (an older version, in case
   that seemed like a safer pin) doesn't help either: it's incompatible with the _current_
   `rescript` compiler (12.3.1) in the opposite direction (`Js.Nullable.t` representation changed).
   There's no version of the two that's simultaneously "old enough for ts2ocaml, new enough for
   rescript@12" without this patch.
3. _(removed)_ **`ts2ocaml`'s `@module` output needs a manual pass regardless of the above.** By
   default it emits `@val` (global) bindings unless you pass `--module es --name <specifier>`; and
   `--name` can't contain a `/` without the CLI trying (and failing) to create nested output
   directories, so getting the real npm subpath specifier (`@e-cline/ts_shapes/index`) into the
   `@module(...)` attributes means running without `--name` and doing a find/replace afterward.
4. _(removed)_ **A ReScript package's `exports` map needs an explicit `"./src/*"` entry to be
   depended on by another ReScript package.** Plain ReScript-to-ReScript imports (not genType/TS
   ones) compile straight to `import ... from "<dep-package>/src/<Module>.res.jsx"` -- ReScript
   resolves cross-package references through its own build graph, not through npm `exports`, and
   always points at the dependency's real `src/` tree (which is also where its _compiled_ output
   lives, since `"in-source": true"` compiles there). If a package's `exports` map only exposes
   `dist/*` (the pattern every other package in this workspace uses, to keep `src/` as an internal
   implementation detail), that import doesn't resolve. Fixed by adding `"./src/*": "./src/*"` to
   any ReScript package meant to be depended on by other ReScript packages (see `res_math`'s
   `package.json`). This does mean such a package's `src/` -- including its raw `.res` source, not
   just the compiled `.res.jsx` -- is npm-resolvable, a slightly wider surface than this workspace's
   usual `dist/`-only convention. The ReScript packages here today have no `exports` map at all:
   they're published as source, so this no longer comes up.
5. **tsdown's CSS Modules output for a library isn't self-injecting.** `vp pack` correctly extracts
   CSS Modules imported from a `.res` file into a real `dist/*.css` with hashed class names (see
   `res_react_ui`'s `Greeting.res` → `dist/Greeting.css`), but no emitted JS file imports it as a
   side effect -- consumers have to `import '@e-cline/res_react_ui_example/Greeting.css'` themselves
   (see `examples/res_react_app/src/main.tsx`). This isn't ReScript-specific (it'd be true of a
   `.tsx` component doing the same CSS Modules import), but it's exactly the kind of thing that's
   invisible until you actually try to consume the built package, which is why it's called out here.
   Relatedly, the default `"./*"` `exports` entry always appends `.js`/`.d.ts` to the matched
   subpath, so it can't resolve a `.css` request on its own -- needed its own
   `"./*.css": "./dist/*.css"` entry.
6. **No single-command live reload from `.res` edit to Vitest/Vite dev server.** `rescript build -w`
   and `vp test watch` / `vp dev` are two independent watch processes; Vite/Vitest happen to pick up
   the rewritten files fine (their own file watcher doesn't care that ReScript wrote them), but
   there's no wiring to launch both with one command today short of a plain shell `&`. A dedicated
   Vite plugin ([`vite-plugin-rescript`](https://github.com/jihchi/vite-plugin-rescript)) exists for
   exactly this, but it works by shelling out to the `rescript` CLI and surfacing errors through
   Vite's overlay -- i.e. the same underlying mechanism, just packaged as a plugin instead of a
   second terminal. It wasn't adopted here because `vp pack`'s bundler (tsdown, on Rolldown) is a
   different pipeline from `vp dev`'s (Vite proper), and a Vite-only plugin wouldn't help the
   `pack`/build path at all; there's no Rolldown-native or `unplugin`-based ReScript plugin as of
   this writing.
7. **Caching pitfall (not a ReScript issue, but worth flagging since it bit this exploration
   directly):** `vp run`'s task cache is keyed enough on declared inputs that running the underlying
   tool (`rescript build`, or the fixup script) by hand outside the task graph, then going back to
   `vp run`, can replay a stale cached result instead of noticing the inputs changed -- especially
   with a compound `command: [...]` array, where each entry is cached as an independent sub-task.
   `vp run --no-cache` (or clearing the cache) resolves it. This only came up because of iterative
   manual `rescript build` invocations while building this exploration, not from normal usage.
8. _(mostly removed: `res_math` is gone, but `examples/res_react_ui`'s `package.json` still has the
   `"./*.res": null` entry described here)_ **A `dist/` full of `.js` files invites accidental
   imports, and a namespace-style entry point has a real (if cosmetic) runtime cost -- neither is
   ReScript-specific.** Each genType-annotated module produces two separate `dist/` files:
   `Point.gen.js` (typed, the intended surface) and `Point.res.js` (genType's raw, untyped input --
   no `.d.ts` of its own). Nothing stops a consumer from importing the untyped one directly
   (`@e-cline/res_math/Point.res` resolves fine by default, since this workspace's usual `"./*"`
   `exports` pattern matches any subpath). Fixed with an explicit `"./*.res": null` entry -- the
   usual `null`-to-block-a-subpath technique for internal-only files, applied to genType's raw
   output. Separately, `src/index.ts` originally re-exported a `Point` namespace
   (`export * as Point from './Point.gen'`) so consumers could write `Point.make(...)`. Confirmed
   with a throwaway plain-TypeScript file (no ReScript involved) that this forces tsdown to
   synthesize an actual runtime object for `Point.foo` property access to work, via a small
   `__exportAll` helper pulled from its own `_virtual/_rolldown/runtime.js` chunk -- true regardless
   of `unbundle`/bundled output, and true for any namespace-style re-export, not just genType's.
   Switched `res_math`/`res_shapes` to flat re-exports
   (`export {make, distance, ...} from './Point.gen'`) instead, which need no runtime object at all
   -- at the cost of the `Point.` grouping (`import {make} from '@e-cline/res_math'` instead of
   `import {Point} from '@e-cline/res_math'; Point.make(...)`).
9. **Not every ReScript package needs genType, and skipping it changes the build wiring, not just
   the annotations.** `res_trees` is meant to be consumed only from other ReScript code, so it has
   no `@genType` at all -- and no `vp pack`-able TypeScript entry point for `build`/`typecheck` to
   work on. That's the default for `makeRescriptLibConfig`; a package with a TS entry point opts in
   with `typescriptSurface: true`. Without it, the config keeps the same task set but makes
   `build`/`typecheck` no-ops (still waiting on the root `res` task), drops the `pack` config, and
   skips test type-checking. Extra tasks (`start`, `demo`, ...) go in its `tasks` option. This is a
   real, supported variant -- not a workaround -- for a package that's purely an implementation
   detail of other ReScript code.
10. **ReScript's `int` wraps at 32 bits; plain JS numbers don't.** Writing a Lehmer/Park-Miller PRNG
    (`seed * 48271 mod 2147483647`, used in `res_trees`'s oracle stress test to shuffle a
    reproducible test order) in `int` silently wrapped around mid-calculation once `seed` grew past
    roughly 2^31 / 48271, producing negative "random" values and, downstream, negative array indices
    -- caught only because the resulting shuffled array visibly had holes in it when logged.
    ReScript's `int` matches OCaml's 32-bit-wrapping semantics, not JS's 53-bit-safe doubles; the
    fix was doing the multiply-then-mod in `float` (an exact JS double up to 2**53) and converting
    back with `Int.toFloat`/`Float.toInt` only at the boundaries. Also encountered along the way:
    `array[i]` indexing now returns `option<'a>` in this compiler version (ReScript 12), not `'a`
    directly -- `Array.getUnsafe(array, i)` is the unchecked equivalent, needed throughout a
    hand-rolled B-tree's array-splicing helpers, which do their own bounds reasoning and don't want
    an `option` in the way. Neither of these is specific to writing a B-tree; both are exactly the
    kind of thing that only surfaces once you write real numeric/array-heavy code instead of a small
    demo module.
11. **Extracting a plain function back out of a `Belt.Id.comparable` needs an OCaml-style
    locally-abstract-type binder, not just ordinary polymorphism.** `res_trees`'s `BTree.make` takes
    a `Belt.Id.comparable<'k, 'id>` (the same first-class-module-based comparator `Belt.Set`/
    `Belt.Map` use) and needs to unpack it once to get a plain `(k, k) => int` to store. Writing
    that unpack (`module Cmp = unpack(id)`) inside an ordinarily-polymorphic function
    (`let make = (~id: Belt.Id.comparable<'k, 'id>, ...) => ...`) fails with "the type of this
    packed module contains variables" -- unpacking an existential type needs the type variables it's
    parameterized over to be _rigid_ within the function body, which plain inferred `'k, 'id`
    aren't. The fix is declaring them as locally-abstract types instead:
    `let make = (type k, type id, ~id: Belt.Id.comparable<k, id>, ...) => ...`. Once unpacked, the
    module's `cmp` field is itself not a plain function but a distinct `Belt_Id.cmp<'a, 'id>`
    wrapper (for the same existential-safety reasons); calling it needs
    `Belt.Id.getCmpInternal(Cmp.cmp)` first. None of this is documented anywhere obvious -- it's the
    kind of thing you only hit by trying to use `Belt.Id` for something other than
    `Belt.Set`/`Belt.Map` themselves. The awkwardness is confined to exactly one place (`make`;
    everything else just threads the already-extracted plain function through), which is itself
    worth knowing: a function that receives an _already-constructed_ value containing a first-class
    module (rather than the module itself) never needs this.
12. **A `module Foo: FooSig = {...}` ascription is real, enforced encapsulation within a single
    `.res` file -- useful when a `.resi` would be too coarse.**
    `res_trees/src/btree/internal/Diff.res` needed to hide its cursor's frame-stack representation
    from its own `walk` function, not just from other files, so a `.resi` (which only controls what
    the _whole module_ exposes to _other_ files) wouldn't have been the right tool. Ascribing an
    inline submodule to an explicit module type (`module Cursor: CursorSig = {...}`) does exactly
    this: even code later in the same file can only see what `CursorSig` lists, confirmed by
    deliberately trying to reference the hidden `frame` type from outside `Cursor` and watching it
    fail to compile. Combined with a `.resi` per file under `internal/` (documenting each module's
    contract to its siblings) and one `.resi` each for the two files meant to be used from outside
    the package (`BTree.res`/`MutableBTree.res`, both hiding their own `t`'s record fields
    entirely), this gives genuine multi-level code-hiding with no framework or build-tool support
    needed -- it's just how ReScript's (OCaml-derived) module system already works.
13. **A JS bundler's `package.json` export conditions (like `@e-cline/js_env`'s dev/prod trick)
    can't be a normal cross-package ReScript dependency, but they still work through an
    `external`.** `res_common`'s `Env.res` needs to hand `isDev`/`isProd` a different concrete value
    in a "development" vs. "production" build, the same way
    [`js_env`](https://github.com/e-cline/js_env) does for TS -- but the ReScript _compiler_
    resolves and type-checks one concrete `.res`/JS module per import at compile time; it has no
    "pick one of two files depending on a build condition" step the way a bundler's module
    resolution does, and `js_env` isn't even a ReScript package for the compiler to resolve in the
    first place. The fix: don't add `js_env` as a `bs-dependencies` entry at all. Instead, `Env.res`
    binds directly to the plain string package specifier --
    `@module("@e-cline/js_env") external isDev: bool = "IS_DEV"` -- which the compiler doesn't look
    inside at all; it just emits a plain `import * as Js_env from "@e-cline/js_env"` (and reads
    `Js_env.IS_DEV` from it) into the compiled `.mjs`, and it's _that_ ordinary JS import a
    bundler's export-condition resolution (and, downstream, its dead-code elimination) applies to
    normally. Every other module needing `isDev` (e.g. `Debug.res`) just references `Env.isDev` as
    an ordinary same-package binding -- no `external` of its own needed, since that's a
    ReScript-to-ReScript reference within one package, not a cross-package one. (This module started
    out as its own package, `res_env`, precisely because `js_env` didn't exist in this repo yet;
    once it did, and `res_env` turned out to be nothing but this one wrapper module, it moved into
    `res_common` instead of staying a single-module package.)
    [`examples/res_tree_shaking`](examples/res_tree_shaking) confirms the mechanism survives a real
    bundle: an `isDev`-only branch reached through `Env.res` is gone from the production output,
    while an `isProd`-only branch (reached the same way) survives.
14. **`Pervasives.raise` is deprecated in ReScript 12 in favor of `throw`,** "to align with
    JavaScript vocabulary" (the compiler's own deprecation message). Neither
    `res_math`/`res_shapes`/ `res_trees` happened to raise an exception anywhere, so this hadn't
    come up in this exploration until `res_common`'s `Debug.res` needed to. Relatedly, a hand-rolled
    ReScript `exception Foo(string)` does _not_ compile to a real JS `Error` -- it has a payload,
    not a `.message` property -- so it doesn't satisfy anything (including Vitest's own
    `toThrow(~message)` matcher) that expects a normal thrown error.
    `JsError.make(message)->JsError.throw` is the fix when a real `Error` (with a working
    `.message`) is actually needed, at the cost of not having a distinct exception identity to
    pattern-match on -- fine when nothing needs to tell "this specific failure" apart from any other
    thrown error, not fine otherwise.
15. **An explicit type annotation on a value (not a function) that would otherwise be polymorphic
    hits the value restriction, same as OCaml.** `let empty: t<'a> = []` (for `ImmutableArray`) and
    `let empty: t<'a> = () => Nil` (for `Sequence`, before being rewritten) both failed with `t<'a>`
    in the `.resi` not matching `t<'_a>` in the `.res` -- the compiler had monomorphized `'a` to
    whatever the first use site happened to need. Wrapping the same value in a trivial function
    (`let make = (): t<'a> => []`) sidesteps it entirely: a function's body is only evaluated per
    call, so there's nothing to monomorphize ahead of time. Worth knowing before reaching for a bare
    `let` + explicit polymorphic type on anything generic that isn't already a function.
16. **Two `int`-arithmetic gotchas beyond gap #10's overflow-wrapping, both hit while porting a
    JavaScript MurmurHash3-derived hash's mixing constants:** first, `Belt`'s bitwise operators live
    on `Int` (`Int.bitwiseXor`/`Int.bitwiseOr`/`Int.shiftLeft`/`Int.shiftRightUnsigned`), not as
    OCaml-style infix keywords (`lxor`/`lor`/`lsl`/`lsr` exist only as a _deprecated_ `Int.Bitwise`
    submodule, each pointing at the `Int.*` function to use instead) -- and there's no
    `Int32`/`Uint32` module at all in `@rescript/runtime` the way OCaml's stdlib has a separate
    boxed `Int32.t`; ReScript's `int` already _is_ the 32-bit type, so the plain `Int` functions
    operate on it directly, no boxing or conversion needed. Second, an integer literal outside
    `int`'s 32-bit signed range (-2147483648..2147483647) -- e.g. murmur3's `2246822507`, which is
    `> 2**31 - 1` -- doesn't compile as written; it has to be rewritten as its 32-bit
    two's-complement signed equivalent (`n - 2**32`, i.e. `-2048144789`), which is the same bit
    pattern and has no effect on a bitwise/`imul`-based algorithm, but is easy to get wrong by hand
    and worth double-checking against a real interpreter rather than mental arithmetic
    (`res_common/tests/Hash_test.res` checks the whole port's output against values from the
    JavaScript version, run in Node, for exactly this reason).
17. **Adding a root `rescript.json` (per the official
    [monorepo setup guide](https://rescript-lang.org/docs/manual/build-monorepo-setup)) has three
    consequences the guide itself doesn't spell out.** First, once a root config exists, `jsx`
    behaves as a genuinely root-only setting -- leaving `"jsx": {"version": 4}` in
    `res_react_ui/rescript.json` (as before the root config existed) now fails with "JSX support is
    not enabled" even though the field is still there; it has to move to the root `rescript.json`
    instead, which is otherwise harmless since only `.res` files that actually use JSX are affected.
    Second, and in the opposite direction, `package-specs`/`suffix` do _not_ work root-only the way
    the guide's own example (which omits them from every package-level config) implies: genType
    reads the _package's own_ `rescript.json` to decide what extension to import its compiled
    sibling under, so a package relying solely on the root's `suffix` gets a genType-generated
    `.gen.tsx` that imports a nonexistent `./Module.bs.js` instead of the real `./Module.res.jsx`,
    breaking `tsc`/`vp pack` for every genType-annotated module -- not just cross-package ones (see
    gap #1). The fix is keeping `package-specs`/`suffix` declared in _both_ the root config and
    every individual package's config (harmless duplication, no inheritance either way). Third,
    root-level `rescript build`/`rescript clean`/`rescript format` only resolve a root
    `dependencies` entry (e.g. `@e-cline/res_trees`) if pnpm has actually symlinked that package
    into the _root's own_ `node_modules` -- which, unlike each ReScript package's own
    `rescript.json` `dependencies` (resolved because that package's `package.json` already lists it
    as a real npm dependency), isn't automatic just from being a pnpm workspace member. Each
    ReScript package needed adding as a `workspace:*` `devDependency` of the _root_ `package.json`
    too, purely so pnpm creates that symlink; also worth knowing, root-level `rescript clean` cleans
    the whole resolved package tree, including third-party ReScript libraries (`rescript-vitest`,
    `@rescript/core`, `@rescript/react`, `rescript-webapi`) -- which is fine (running
    `rescript build` again regenerates everything it cleaned, the same as for any other dependency
    in the tree) but surprising the first time a `pnpm install` right afterward doesn't appear to
    bring the files back, since they're build-generated, not shipped in those packages' npm
    tarballs.

## What the research surfaced (beyond what's demoed above)

- **ReScript 12** (Dec 2025) rewrote the build system around **Rewatch** (now the default engine
  behind `rescript build`/`-w`; legacy `bsb` is reachable via `rescript-legacy`, slated for removal
  in v13), which was built specifically with monorepos in mind (parallel compilation,
  pnpm-symlink-aware resolution). There's also an
  [official monorepo setup guide](https://rescript-lang.org/docs/manual/build-monorepo-setup).
- **genType is no longer a separate tool** -- the standalone project was archived in Nov 2023 and
  folded into the compiler as of ReScript 10.1+, configured via `gentypeconfig` in `rescript.json`.
  This is why nothing in this exploration needed a separate genType install.
- **`ts2ocaml`** (`@ocsigen/ts2ocaml`, currently only at ReScript-targeting maturity under the
  `beta` npm dist-tag,`2.0.0-beta.x`) is a real, functioning `.d.ts` → ReScript binding generator --
  confirmed here against a real, moderately complex generic function type (`Comparator<T>`, a
  rest-parameter generic function, and a structural `interface`) -- but it's explicitly beta,
  undocumented for monorepo/ cross-package scenarios, and (per its own docs) not designed to handle
  indirect re-exports or some inheritance patterns. Treat its output as a generated starting point
  to review and occasionally patch, the same way you'd review any codegen output, not as a black
  box.
- **No mature alternative exists** for automatic TypeScript-to-ReScript binding generation;
  hand-written `external` bindings remain the normal, expected practice in the ReScript community
  for anything ts2ocaml doesn't handle well.
- **`@rescript/react` 0.15** supports React 19 and JSX v4/uncurried mode (the norm now, not an
  opt-in). A genType-annotated component compiles to an ordinary function component with real prop
  types -- confirmed indistinguishable, from the consuming `.tsx` side, from a hand-written React
  component.
- **CSS/styling in ReScript is fragmented, with no single dominant answer**: CSS Modules (used here)
  work but with no ReScript-side type safety by default; `typed-css-classes` adds typed class-name
  codegen; [`@jvlk/rescript-css`](https://github.com/jderochervlk/rescript-css) is a genuine Vite
  plugin for authoring styles inside `.res` but is very early (bleeding-edge version requirements,
  minimal adoption at last check). Emotion-style bindings and inline style helpers are also
  documented officially. Expect to pick and adapt, not adopt a default.
- `@rescript/core` and `rescript-webapi` are reasonable, actively-published options for further
  ReScript-authored stdlib/WebAPI needs beyond what's demoed here. (An earlier draft of this section
  speculated about `@greenfinity/rescript-vitest` for testing, sight unseen; having since actually
  used `cometkim/rescript-vitest` for real -- see "Testing directly in ReScript" above -- that
  speculation is replaced rather than left standing next to a tested result.)

## VSCode integration

Added `chenglou92.rescript-vscode` to `.vscode/extensions.json`, and `lib/bs`/`lib/ocaml`
(ReScript's per-package build-artifact cache directories) to `.vscode/settings.json`'s
`files.watcherExclude` / `search.exclude`. The OCaml extension (`ocamllabs.ocaml-platform`) is
recommended too, and `ocaml.sandbox` points it at the PPX's local opam switch.

No `rescript.settings.binaryPath` override was added: per the extension's documented behavior, it
resolves the `rescript` binary and language server by finding the nearest `rescript.json` to the
currently open file and walking up to that package's own `node_modules/.bin/rescript` -- which every
ReScript package here has, as a direct `devDependency`, through pnpm's per-package
`node_modules/.bin` layout. This should work without extra configuration for a workspace with
several `rescript.json` files the way this one now has, but wasn't independently verified inside a
running VSCode instance in this environment -- worth a quick sanity check the first time you open
this workspace in VSCode with the extension installed.

## If you want to go further

- If a TypeScript-facing ReScript package that uses another package's genType types comes back,
  check on the upstream genType bug (#1 above) before patching around it again.
- `ts2ocaml`'s output (#2/#3) was good enough to lean on for real packages, but budget time for the
  one-time `Ts2ocaml.res` patch and reviewing generated bindings by hand, the same way you'd review
  any other generated code before trusting it.
- If a package needs real hot-reload from `.res` edits (not just "Vitest happens to notice the file
  changed"), evaluate `vite-plugin-rescript` directly rather than the two-terminal approach used
  here -- it wasn't adopted only because this exploration prioritized the `vp pack`/build path,
  which it doesn't help with anyway.
