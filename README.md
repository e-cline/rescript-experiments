# rescript-experiments

Some experiments written in [ReScript](https://rescript-lang.org/). Mostly written with Claude.

WARNING: None of this is intended for real production use.

## Weft

Weft is the UI framework in here: `weft` (components, hooks and a fiber reconciler), `weft_dom` (the
DOM renderer) and `weft_signals` (hooks for reading `signals`), plus the `weft_app` example. Server
components for it are under way: `weft_server` and `weft_vite_plugin`, with the `weft_notes` and
`weft_split` examples.

## Packages

| Package                                               | What it is                                                                                                                                           |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`@e-cline/common`](packages/common)                  | Utilities with no direct `Belt` equivalent: array helpers, an `ImmutableArray`, debug-only assertions, hashing, and a lazy sequence type.            |
| [`@e-cline/priority_queue`](packages/priority_queue)  | Priority queues: a mutable array-backed binary heap and an immutable leftist heap.                                                                   |
| [`@e-cline/trees`](packages/trees)                    | Persistent sorted maps (a B+tree, an AVL tree and a chunked AVL tree), with mutable variants and diffing that takes advantage of structural sharing. |
| [`@e-cline/signals`](packages/signals)                | Reactive signals: atoms, computeds and effects, with diff-driven history for incremental consumers.                                                  |
| [`@e-cline/signal_maps`](packages/signal_maps)        | A sorted, signal-backed map whose derived views update incrementally. Built on the two packages above.                                               |
| [`@e-cline/servy`](packages/servy)                    | A small framework for HTTP servers on the Web-standard `Request`/`Response` APIs, running on Node.                                                   |
| [`@e-cline/weft`](packages/weft)                      | A React-like component library: `@weft.component` components and hooks, rendered by a fiber reconciler through a pluggable host renderer.            |
| [`@e-cline/weft_dom`](packages/weft_dom)              | The DOM renderer for `weft`: render components into a browser page.                                                                                  |
| [`@e-cline/weft_signals`](packages/weft_signals)      | Hooks for reading `signals` atoms and computeds from `weft` components.                                                                              |
| [`@e-cline/weft_server`](packages/weft_server)        | Server components for Weft: render on the server into a streamed payload, decode it on the client, with entrypoints loaded on demand.                |
| [`@e-cline/weft_vite_plugin`](tools/weft_vite_plugin) | The Vite plugin for Weft's server components: server and client environments, an entrypoint per chunk, the boundary enforced, dev and build.         |

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
`SignalMaps`, `Servy`, `Weft`, `WeftDom`, `WeftSignals`, `WeftServer`), so `Signals.Atom.make` works
without an `open`. The packages ship as ReScript source, and your project's `rescript build`
compiles them along with your own code.

## Also in this repository

These aren't published:

- [`examples/`](examples) -- an HTTP server built with `servy`, a React component written in
  ReScript and the TypeScript React app consuming it, a todo app built with `weft`, a notes app and
  an app code-split with Weft's server components (with tests through the plugin's harness, and in a
  browser), a tree-shaking check, and a use of the PPX below.
- [`packages/trees/benchmarks`](packages/trees/benchmarks),
  [`packages/signals/benchmarks`](packages/signals/benchmarks),
  [`packages/signal_maps/benchmarks`](packages/signal_maps/benchmarks) and
  [`packages/weft/benchmarks`](packages/weft/benchmarks) -- benchmarks for `trees`, `signals`,
  `signal_maps` and `weft`, run against a bundled and minified build.
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
