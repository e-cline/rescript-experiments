# ReScript PPXs

The workspace's PPXs, written in OCaml with [ppxlib](https://github.com/ocaml-ppx/ppxlib):

- [`pretty_print`](pretty_print) (`@e-cline/ppx_pretty_print`) -- `@prettyPrint` on a type derives
  pretty-printers for it.
- [`weft`](weft) (`@e-cline/ppx_weft`) -- `@weft.component`, Weft's component attribute (see
  [the server components plan](../../docs/weft_server_components_plan.md)), tested by
  [`weft_tests`](weft_tests).

They share one OCaml toolchain, set up by `setup.sh` in this directory.

## The toolchain

Building a PPX needs [opam](https://opam.ocaml.org/) installed (and `opam init` run once). Nothing
else: the build sets up the rest.

```bash
pnpm --filter @e-cline/ppx_pretty_print exec vp run build
```

Each PPX's `build` task depends on the root `ppx:setup` task, which runs `setup.sh`: it creates a
global opam switch named `rescript_ppx` (under `~/.opam`) holding exactly the compiler and package
versions in `rescript_ppx.opam.locked`. The PPXs' builds then run dune from it with
`opam exec --switch=rescript_ppx`. Your current opam switch, and whatever OCaml it has, is neither
used nor touched. Creating the switch compiles OCaml, which takes a few minutes; on later builds
`setup.sh` does nothing unless the lock file differs from the one the switch was last installed from
(a copy of which it keeps inside the switch). It runs once per build, not once per PPX, so two PPX
builds never install into the switch at the same time.

Because the switch lives outside the checkout, every clone and git worktree on the machine shares
it, and only the first one to build pays for compiling OCaml. The catch is that checkouts with
different lock files -- say, a branch bumping ppxlib -- share it too: each build re-syncs the switch
to its own lock file, which is quick for a package bump but recompiles everything when the OCaml
version differs, and a build in one checkout can change the switch under a build running in the
other. Avoid building such checkouts at the same time; once the lock file change is merged
everywhere, they agree again.

To start over, `opam switch remove rescript_ppx` and build again. Checkouts from before the switch
was shared used one named `ppx_pretty_print`, and older ones a local switch in
`pretty_print/_opam/`; both can be deleted (`opam switch remove ppx_pretty_print`).

The root-level `res` task depends on every PPX's `build` task, so `pnpm build` / `pnpm test` from
the repo root build the PPXs first -- which also means **the whole workspace's build needs opam**.

To change a dependency: edit `rescript_ppx.opam` (and the PPXs' `dune-project` files, which state
the same ranges for their own packages), then from this directory
`opam install . --deps-only --switch=rescript_ppx`, and regenerate the lock file with
`opam lock . --switch=rescript_ppx`.

The versions are pinned for a reason. The ReScript compiler hands a PPX a frozen, OCaml 4.06-shaped
version of its AST, and ppxlib 0.34 is the last release that reads it (0.35 dropped every AST older
than 4.08). ppxlib 0.34 in turn needs OCaml < 5.4.

After changing a PPX, rebuild it and then rebuild the ReScript code using it. If the change doesn't
seem to take effect, `pnpm rescript:clean` first: the ReScript build decides what to recompile from
the `.res` sources, not from the PPX executable.
