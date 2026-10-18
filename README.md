# rescript-experiments

Some experiments written in [ReScript](https://rescript-lang.org/). Mostly written with Claude.

WARNING: None of this is intended for real production use.

## Packages

| Package                                              | What it is                                                                                                                                           |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`@e-cline/common`](packages/common)                 | Utilities with no direct `Belt` equivalent: array helpers, an `ImmutableArray`, debug-only assertions, hashing, and a lazy sequence type.            |
| [`@e-cline/priority_queue`](packages/priority_queue) | Priority queues: a mutable array-backed binary heap and an immutable leftist heap.                                                                   |
| [`@e-cline/trees`](packages/trees)                   | Persistent sorted maps (a B+tree, an AVL tree and a chunked AVL tree), with mutable variants and diffing that takes advantage of structural sharing. |
| [`@e-cline/signals`](packages/signals)               | Reactive signals: atoms, computeds and effects, with diff-driven history for incremental consumers.                                                  |
| [`@e-cline/signal_maps`](packages/signal_maps)       | A sorted, signal-backed map whose derived views update incrementally. Built on the two packages above.                                               |
| [`@e-cline/server`](packages/server)                 | A small framework for HTTP servers on the Web-standard `Request`/`Response` APIs, running on Node.                                                   |
| [`@e-cline/fiber`](packages/fiber)                   | A React-like component library: `@jsx.component` components and hooks, rendered by a fiber reconciler through a pluggable host renderer.             |
| [`@e-cline/fiber_dom`](packages/fiber_dom)           | The DOM renderer for `fiber`: render components into a browser page.                                                                                 |
| [`@e-cline/fiber_signals`](packages/fiber_signals)   | Hooks for reading `signals` atoms and computeds from `fiber` components.                                                                             |

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
`SignalMaps`, `Server`, `Fiber`, `FiberDom`, `FiberSignals`), so `Signals.Atom.make` works without
an `open`. The packages ship as ReScript source, and your project's `rescript build` compiles them
along with your own code.

## Also in this repository

These aren't published:

- [`examples/`](examples) -- an HTTP server built with `server`, a React component written in
  ReScript and the TypeScript React app consuming it, a todo app built with `fiber`, a tree-shaking
  check, and a use of the PPX below.
- [`packages/trees/benchmarks`](packages/trees/benchmarks),
  [`packages/signals/benchmarks`](packages/signals/benchmarks),
  [`packages/signal_maps/benchmarks`](packages/signal_maps/benchmarks) and
  [`packages/fiber/benchmarks`](packages/fiber/benchmarks) -- benchmarks for `trees`, `signals`,
  `signal_maps` and `fiber`, run against a bundled and minified build.
- [`tools/benchmarking`](tools/benchmarking) -- what benchmark packages share: ReScript bindings to
  mitata and a seeded PRNG.
- [`tools/ppx/pretty_print`](tools/ppx/pretty_print) -- an example ReScript PPX, written in OCaml,
  that derives pretty-printers for types.
- [`RESCRIPT.md`](RESCRIPT.md) -- notes on integrating ReScript with the Vite+ toolchain, including
  the rough edges found along the way.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up, build and test the workspace, and
[SECURITY.md](SECURITY.md) for reporting a vulnerability.

## License

[MIT](LICENSE)
