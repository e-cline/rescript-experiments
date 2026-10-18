# @e-cline/ppx_weft

A [ReScript](https://rescript-lang.org/) PPX for Weft's component attribute, `@weft.component`. It's
the start of server components for Weft; see
[the plan](../../../docs/weft_server_components_plan.md) for where it's going.

```rescript
@@jsxConfig({version: 4, module_: "Weft.Jsx"})

@weft.component                       // a shared component
let make = (~name: string) => <p> {Weft.Jsx.string(name)} </p>

@weft.component({kind: Server})       // will run only on the server
let make = ...

@weft.component({kind: Entrypoint})   // will be where client code starts
let make = ...
```

## What it does (so far)

This is phase 0 of the plan. The PPX replaces each `@weft.component` with a plain `@jsx.component`,
which ReScript's JSX transform then handles as usual (the compiler runs PPXs before that transform).
So for now **every kind compiles as a shared component**, exactly as `@jsx.component` would. What
makes the kinds different -- rewriting `async` server components, marking entrypoints, the file
markers the Vite plugin reads -- comes in phase 2.

It already checks the attribute, so a mistake is a compile error rather than silently ignored:

- the argument is absent, `{kind: Server}` or `{kind: Entrypoint}`;
- it's on a `let` binding, or in an interface file on a `let` declaration (the only places the JSX
  transform looks);
- a binding has it at most once, and not together with `@jsx.component`.

**Without the PPX**, the compiler ignores `@weft.component` (it doesn't know the attribute), so the
component gets no `props` type, and every use of it fails to type-check: the component "has type"
`(~name: string) => ...` where the JSX module's `component<'a>` was expected (the full message is in
[`../weft_tests/canaries/WithoutThePpx.expected`](../weft_tests/canaries/WithoutThePpx.expected)).
If you see that for a `@weft.component` component, the PPX isn't in the package's `ppx-flags`.

## Using it in a package

In the package's `package.json`:

```json
"dependencies": {
  "@e-cline/ppx_weft": "workspace:*"
}
```

In its `rescript.json` (the generated code needs nothing from this package, so it doesn't go in
`dependencies` there):

```json
"ppx-flags": ["@e-cline/ppx_weft/ppx"]
```

An interface file declaring a `@weft.component` needs its own `@@jsxConfig` line, as with
`@jsx.component`.

## Layout

- `ppx_src/ppx_weft.ml` -- the PPX, using [ppxlib](https://github.com/ocaml-ppx/ppxlib).
- `ppx_src/bin/main.ml` -- the executable wrapping it, which is what the ReScript compiler runs.
- `ppx` -- the shell script `ppx-flags` points at; forwards to the dune-built executable.

Its tests are a package of their own, [`../weft_tests`](../weft_tests):

- `fixtures/` -- components compiled through the PPX (every kind, nested modules, an interface,
  `Weft.Jsx`). Their compiled `.res.js` is committed, so a change to what the PPX produces shows up
  in review.
- `specs/` -- the tests: the fixtures render exactly as their `@jsx.component` twins do, assertions
  on the compiled output phase 2 will build on, and the failing files below.
- `errors/` -- each misuse of the attribute, with the error it gives (`<Name>.expected`).
- `canaries/` -- compiler behaviours the PPX's design depends on, compiled without it, so a ReScript
  upgrade that changes one fails a test by name.

The failing files are `.res.in`, so neither the ReScript build nor the formatter picks them up; the
tests compile each with `bsc` from a temporary directory. After an intended change to an error, run
the tests with `-u` to rewrite its `.expected` file.

## Building

Building it needs [opam](https://opam.ocaml.org/); [`../README.md`](../README.md) covers the
toolchain, which every PPX in `tools/ppx` shares.

```bash
pnpm --filter @e-cline/ppx_weft exec vp run build
```

The root-level `res` task depends on that, so `pnpm build` / `pnpm test` from the repo root build it
first. [`../pretty_print/README.md`](../pretty_print/README.md) has notes on writing a ReScript 12
PPX.
