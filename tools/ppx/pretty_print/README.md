# @e-cline/ppx_pretty_print

An example [ReScript](https://rescript-lang.org/) PPX: annotate a type declaration with
`@prettyPrint` and it derives functions that render the type's values as pretty-printed strings.

```rescript
@prettyPrint
type point = {x: float, y: float}

@prettyPrint
type shape =
  | Circle({center: point, radius: float})
  | Polygon(array<point>)

shape_prettyPrint(Circle({center: {x: 0.0, y: 0.0}, radius: 2.5}))
// Circle({center: {x: 0.0, y: 0.0}, radius: 2.5})
```

Output is ReScript-like syntax. A value that fits in 80 columns stays on one line; one that doesn't
is broken up, one element per line:

```
{
  id: 7n,
  customer: {name: "Ada"},
  items: [{sku: "A", quantity: 2, price: (9.99, #usd)}],
  status: #shipped("TRACK-42"),
}
```

See `../../../examples/pretty_print` for a package using it. Targets ReScript 12+.

## What's generated

For each annotated `type foo`, right after the declaration:

- `foo_prettyPrint: foo => string` -- the value, rendered 80 columns wide.
- `foo_toDoc: foo => PrettyPrint.doc` -- the value before layout. It's what other printers call, and
  what `PrettyPrint.render(~width, doc)` takes to render at another width.

A type with parameters gets functions taking a printer per parameter first:
`tree_prettyPrint: ('a => PrettyPrint.doc, tree<'a>) => string`, called as
`tree_prettyPrint(PrettyPrint.int, tree)`.

In an interface file (`.resi`), `@prettyPrint` adds the matching `let` declarations instead, so
annotate the type in both files to export its printers.

Supported in an annotated type:

- Records (including optional `name?: typ` fields, left out of the output when unset), variants
  (including inline-record payloads), and aliases.
- `int`, `float`, `string`, `bool`, `bigint`, `unit`, `option`, `array`, `list`, `dict`, `result`,
  tuples, and closed polymorphic variants. Function types print as `<fun>`.
- Any other named type, `foo` or `Mod.t`, provided a `foo_toDoc` / `Mod.t_toDoc` is in scope --
  normally because that type is annotated too, but a hand-written one works just as well (build it
  from `PrettyPrint.text` and friends; see `src/PrettyPrint.resi`). If there isn't one, compilation
  fails with "The value foo_toDoc can't be found", pointing at the type reference.
- `@prettyPrint.opaque` on a field or type expression (`placedAt: @prettyPrint.opaque Date.t`) to
  print `<opaque>` instead of needing a printer.

Anything else (abstract types, object types, open polymorphic variants, ...) is a compile error at
the offending type.

## Layout

- `ppx_src/ppx_pretty_print.ml` -- the PPX: an OCaml program using
  [ppxlib](https://github.com/ocaml-ppx/ppxlib). Its header comment walks through what it generates.
- `ppx_src/bin/main.ml` -- the executable wrapping it, which is what the ReScript compiler runs.
- `ppx` -- the shell script `ppx-flags` points at; forwards to the dune-built executable.
- `src/PrettyPrint.res` -- the runtime: the ReScript module generated code calls into, where the
  actual layout logic lives. Keeping that out of the PPX keeps the generated code (and the OCaml)
  small.

## Building

The PPX is OCaml, so building it needs [opam](https://opam.ocaml.org/) installed (and `opam init`
run once). Nothing else: the `build` task sets up the rest.

```bash
pnpm --filter @e-cline/ppx_pretty_print exec vp run build
```

That first runs `setup.sh`, which creates a global opam switch named `ppx_pretty_print` (under
`~/.opam`) holding exactly the compiler and package versions in `ppx_pretty_print.opam.locked`, then
runs dune from it with `opam exec --switch=ppx_pretty_print`. Your current opam switch, and whatever
OCaml it has, is neither used nor touched. Creating the switch compiles OCaml, which takes a few
minutes; on later builds `setup.sh` does nothing unless the lock file differs from the one the
switch was last installed from (a copy of which it keeps inside the switch).

Because the switch lives outside the checkout, every clone and git worktree on the machine shares
it, and only the first one to build pays for compiling OCaml. The catch is that checkouts with
different lock files -- say, a branch bumping ppxlib -- share it too: each build re-syncs the switch
to its own lock file, which is quick for a package bump but recompiles everything when the OCaml
version differs, and a build in one checkout can change the switch under a build running in the
other. Avoid building such checkouts at the same time; once the lock file change is merged
everywhere, they agree again.

To start over, `opam switch remove ppx_pretty_print` and build again. Checkouts set up before the
switch was global have a now-unused local switch in `_opam/`, which can be deleted.

The root-level `res` task depends on that `build` task, so `pnpm build` / `pnpm test` from the repo
root build the PPX first -- which also means **the whole workspace's build needs opam**.

To change a dependency: edit `dune-project`, then from this directory
`opam install . --deps-only --switch=ppx_pretty_print`, and regenerate the lock file with
`opam lock . --switch=ppx_pretty_print`.

The versions are pinned for a reason. The ReScript compiler hands a PPX a frozen, OCaml 4.06-shaped
version of its AST, and ppxlib 0.34 is the last release that reads it (0.35 dropped every AST older
than 4.08). ppxlib 0.34 in turn needs OCaml < 5.4.

After changing the PPX, rebuild it and then rebuild the ReScript code using it. If the change
doesn't seem to take effect, `pnpm rescript:clean` first: the ReScript build decides what to
recompile from the `.res` sources, not from the PPX executable.

## Using it in a package

In the package's `package.json`, depend on this one:

```json
"dependencies": {
  "@e-cline/ppx_pretty_print": "workspace:*"
}
```

In its `rescript.json`, list it both as a dependency (for the `PrettyPrint` runtime module) and as a
PPX:

```json
"dependencies": ["@e-cline/ppx_pretty_print"],
"ppx-flags": ["@e-cline/ppx_pretty_print/ppx"]
```

## Notes on writing a ReScript 12 PPX

Things that weren't obvious, for whoever writes the next one:

- A PPX is any executable taking `<input file> <output file>` arguments, both binary-marshalled
  ASTs. ppxlib's `Driver.run_as_ppx_rewriter` implements that protocol.
- The AST isn't ReScript's own but its `Parsetree0` compatibility layer, with ReScript-only
  constructs encoded in OCaml 4.06 terms. The ones generated code runs into: a function
  `(a, b) => body` is `fun a -> fun b -> body` wrapped in a `Function$` constructor carrying a
  `res.arity` attribute; a function type is likewise wrapped in `function$<_, [#Has_arity2]>`; an
  optional record field has a `res.optional` attribute; a string literal has the delimiter `"js"`.
  `compiler/ml/ast_mapper_to0.ml` and `ast_mapper_from0.ml` in the
  [compiler's sources](https://github.com/rescript-lang/rescript) are the reference.
- Errors raised with ppxlib's `Location.raise_errorf` come out as ordinary ReScript compile errors
  at the given location.
- [ppx_spice](https://github.com/mununki/ppx_spice) is a good, larger PPX of the same shape (derive
  functions from annotated types) to read.
  [rescript-ppxlib](https://github.com/mununki/rescript-ppxlib) is a newer library that works on
  ReScript's native AST instead, but needs a compiler fork as of ReScript 12.3.
