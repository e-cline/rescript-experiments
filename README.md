# rescript-experiments

Some experiments written in [ReScript](https://rescript-lang.org/). Mostly written with Claude.

WARNING: None of this is intended for real production use.

## Weft

Weft is the UI framework in here: `weft` (its public API, re-exporting the next two), `weft_core`
(components, hooks and a fiber reconciler), `weft_dom` (the DOM renderer) and `weft_signals` (hooks
for reading `signals`), plus the `weft_app` example.

## Packages

| Package                                              | What it is                                                                                                                                           |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`@e-cline/common`](packages/common)                 | Utilities with no direct `Belt` equivalent: array helpers, an `ImmutableArray`, debug-only assertions, hashing, and a lazy sequence type.            |
| [`@e-cline/priority_queue`](packages/priority_queue) | Priority queues: a mutable array-backed binary heap and an immutable leftist heap.                                                                   |
| [`@e-cline/trees`](packages/trees)                   | Persistent sorted maps (a B+tree, an AVL tree and a chunked AVL tree), with mutable variants and diffing that takes advantage of structural sharing. |
| [`@e-cline/signals`](packages/signals)               | Reactive signals: atoms, computeds and effects, with diff-driven history for incremental consumers.                                                  |
| [`@e-cline/signal_maps`](packages/signal_maps)       | A sorted, signal-backed map whose derived views update incrementally. Built on the two packages above.                                               |
| [`@e-cline/servy`](packages/servy)                   | A small framework for HTTP servers on the Web-standard `Request`/`Response` APIs, running on Node.                                                   |
| [`@e-cline/weft`](packages/weft)                     | Weft's public API: `weft_core` and `weft_dom` behind one `Weft` module. The package to depend on.                                                    |
| [`@e-cline/weft_core`](packages/weft_core)           | A React-like component library: `@jsx.component` components and hooks, rendered by a fiber reconciler through a pluggable host renderer.             |
| [`@e-cline/weft_dom`](packages/weft_dom)             | The DOM renderer for `weft_core`: render components into a browser page.                                                                             |
| [`@e-cline/weft_signals`](packages/weft_signals)     | Hooks for reading `signals` atoms and computeds from `weft_core` components.                                                                         |

These are at version 0.0.x: the APIs are still changing, and any release may break them.

## Using a package

**None of these packages is on npm yet.** The steps below are how you'll use one once it's
published; until then, the way to try one is to clone this repository and work inside it (see
[CONTRIBUTING.md](CONTRIBUTING.md)).

The ReScript packages need ReScript 12. Install one alongside the compiler and its runtime:

```bash
npm install @e-cline/signals rescript @rescript/runtime
```

Then list it in your `rescript.json`:

```json
{
  "dependencies": ["@e-cline/signals"]
}
```

Each package's modules sit under a namespace named after it (`Signals`, `Trees`, `Common`,
`SignalMaps`, `Servy`, `WeftCore`, `WeftDom`, `WeftSignals`), so `Signals.Atom.make` works without
an `open`. (`weft` is the exception: a single `Weft` module.) The packages ship as ReScript source,
and your project's `rescript build` compiles them along with your own code.

## Also in this repository

These aren't published:

- [`examples/`](examples) -- an HTTP server built with `servy`, a React component written in
  ReScript and the TypeScript React app consuming it, a todo app built with `weft_core`, a
  tree-shaking check, and a use of the PPX below.
- [`packages/trees/benchmarks`](packages/trees/benchmarks),
  [`packages/signals/benchmarks`](packages/signals/benchmarks),
  [`packages/signal_maps/benchmarks`](packages/signal_maps/benchmarks) and
  [`packages/weft_core/benchmarks`](packages/weft_core/benchmarks) -- benchmarks for `trees`,
  `signals`, `signal_maps` and `weft_core`, run against a bundled and minified build.
- [`tools/benchmarking`](tools/benchmarking) -- what benchmark packages share: ReScript bindings to
  mitata and a seeded PRNG.
- [`tools/ppx/pretty_print`](tools/ppx/pretty_print) -- an example ReScript PPX, written in OCaml,
  that derives pretty-printers for types.
- [`tools/ppx/weft`](tools/ppx/weft) -- the PPX for Weft's `@weft.component` attribute, the start of
  [server components for Weft](docs/weft_server_components_plan.md), with its tests in
  [`tools/ppx/weft_tests`](tools/ppx/weft_tests).
- [`RESCRIPT.md`](RESCRIPT.md) -- notes on integrating ReScript with the Vite+ toolchain, including
  the rough edges found along the way.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up, build and test the workspace, and
[SECURITY.md](SECURITY.md) for reporting a vulnerability.

## License

[MIT](LICENSE)
