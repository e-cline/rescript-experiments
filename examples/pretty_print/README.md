# @e-cline/pretty_print_example

An example ReScript package using the `@prettyPrint` PPX from `../../tools/ppx/pretty_print` (see
its README for what the PPX does, and for the one-time OCaml setup building it needs).

Using the PPX takes two things, both in this package's `rescript.json`: `@e-cline/ppx_pretty_print`
in `dependencies` (for the `PrettyPrint` runtime module that generated code calls) and
`@e-cline/ppx_pretty_print/ppx` in `ppx-flags` (the PPX itself).

- `src/Geometry.res` -- the basics: records, variants, and types that use each other.
- `src/Tree.res`, `src/Tree.resi` -- a recursive type with a type parameter, and exporting its
  printers through an interface file.
- `src/Order.res` -- everything else: optional fields, built-in containers, tuples, polymorphic
  variants, types from other modules, `@prettyPrint.opaque`, and a hand-written printer.
- `src/Demo.res` -- prints a few values.
- `tests/PrettyPrinters_test.res` -- tests of the generated printers.

```bash
pnpm --filter @e-cline/pretty_print_example exec vp run demo
```

```bash
pnpm --filter @e-cline/pretty_print_example exec vp run test
```
