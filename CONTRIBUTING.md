# Contributing

Bug reports and pull requests are welcome. For anything larger than a small fix, please open an
issue first so the approach can be agreed before you spend time on it.

## Setup

### Prerequisites

Install these once per machine:

- [Node.js](https://nodejs.org/) 22 or later.
- [pnpm](https://pnpm.io/installation). The version is pinned by `packageManager` in `package.json`.
- [opam](https://opam.ocaml.org/doc/Install.html), the OCaml package manager, followed by a one-time
  `opam init`. It's needed because the workspace includes a ReScript PPX written in OCaml
  (`tools/ppx/pretty_print`), which every build compiles first.

Everything else is installed by the steps below: Vite+ (`vp`, the task runner, bundler, test runner,
formatter and linter), the ReScript compiler, and the OCaml toolchain.

### Install and build

```bash
pnpm install
```

```bash
pnpm run build
```

**The first build takes a few minutes**, because it compiles OCaml. See below.

### The OCaml toolchain

There's no OCaml version to install or select by hand. The PPX's build task runs
`tools/ppx/pretty_print/setup.sh`, which creates a global opam switch named `ppx_pretty_print`
(under `~/.opam`) containing exactly the compiler and packages pinned in
`tools/ppx/pretty_print/ppx_pretty_print.opam.locked` -- currently OCaml 5.3.0 and ppxlib 0.34.0.

- The build always uses that switch, via `opam exec --switch=ppx_pretty_print`. Your current switch,
  and whatever OCaml the machine has otherwise, is neither used nor changed, and there's no need to
  run `eval $(opam env)`.
- The switch is shared by every clone and git worktree on the machine, so only the first build
  compiles OCaml. After that, `setup.sh` does nothing unless the lock file has changed, in which
  case the next build brings the switch back in sync with it. (Checkouts with different lock files
  therefore re-sync it back and forth; see `tools/ppx/pretty_print/README.md`.)
- To start over, `opam switch remove ppx_pretty_print` and build again.

The versions are pinned because ReScript only works with a narrow range of them; see
`tools/ppx/pretty_print/README.md` for why, and for how to change a dependency and regenerate the
lock file.

## Scripts

Build everything, or run every package's tests:

```bash
pnpm run build
```

```bash
pnpm run test
```

Run every benchmark package (a package's `benchmarks/` directory is a package of its own, built on
[`tools/benchmarking`](tools/benchmarking); `test` only checks that each one still runs, measuring a
single benchmark):

```bash
pnpm run bench
```

To check whether a change made a package faster, compare its benchmarks at a git ref with the
working tree, alternating between the two over several processes (see
[`tools/benchmarking`](tools/benchmarking#measuring-over-several-processes-res-bench)):

```bash
pnpm --filter @e-cline/res_trees_benchmarks exec vp run bench:compare main
```

Compile just the ReScript code (all packages, PPX included):

```bash
pnpm exec vp run -w res
```

Run a task in a sub-package:

```
pnpm --filter <package> exec vp run <task>
```

Format, and check formatting and lint:

```bash
pnpm run fmt
```

```bash
pnpm run check
```

Clean up artifacts. This deletes every gitignored file: `node_modules`, `dist`, the ReScript
compiler's output (`lib/`, `*.res.jsx`, `*.gen.tsx`), and the PPX's `_build`. The opam switch lives
outside the repository, so it survives this:

```bash
git clean -fdX
```

## Before you commit

`pnpm install` sets up a pre-commit hook (through Vite+'s `vp config`) that formats and lints the
files you've staged: `vp check --fix` for TypeScript, JSON, Markdown and the like, and
`rescript format` for `.res`/`.resi` files. To run the same checks over the whole repository (after
a build -- the type check covers TypeScript that imports files the ReScript compiler generates):

```bash
pnpm run check
```

CI runs that check, the build and every package's tests on each pull request.

## Changesets

A pull request that changes a published package needs a
[changeset](https://github.com/changesets/changesets) describing the change:

```bash
pnpm changeset
```

Pick the packages affected and a bump for each (patch, minor or major), and write a one-line
summary -- it becomes the changelog entry. Commit the file it creates under `.changeset/` with your
change. Changes to examples, tests, docs or tooling don't need one.

## Releasing

Publishing is a manual step, done by a maintainer:

1. Pull requests merge to `main` with their changesets.
2. When it's time to release, apply the pending changesets on `main`. This bumps versions, updates
   each package's `CHANGELOG.md`, and deletes the changeset files:

   ```bash
   pnpm run version-packages
   ```

   The changelog entries link to pull requests, which needs a GitHub token in `GITHUB_TOKEN` (for
   example `GITHUB_TOKEN=$(gh auth token) pnpm run version-packages`). Commit the result and push
   it.

3. Run the [release workflow](.github/workflows/release.yml) from the repository's Actions tab. It
   runs the tests, then publishes every package whose version isn't on npm yet and pushes a git tag
   for each. It refuses to run while changesets are still pending.

The ReScript packages are published as source (`.res`/`.resi` plus `rescript.json`), which is what
ReScript's build system expects of a dependency, so none of them has a build step.
