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

## What it does

The PPX replaces each `@weft.component` with a plain `@jsx.component`, which ReScript's JSX
transform then handles as usual (the compiler runs PPXs before that transform), and then, by kind:

- **Shared** (no argument): nothing else. It compiles exactly as `@jsx.component` would.
- **Server**: an `async` component is rewritten to be synchronous, returning a `WeftCore.Lazy`
  element around its body's promise:

  ```rescript
  let make = async (~id) => body
  // becomes
  let make = (~id) => WeftCore.Lazy.fromPromise((async () => body)())
  ```

  (The JSX transform can't take an async component itself: it wraps one in the standard library's
  `Jsx.promise`, which doesn't fit Weft's element type.) The file gets
  `@@directive("'use weft server'")`, so its compiled JavaScript starts with that directive.

- **Entrypoint**: after the binding, `WeftCore.Entrypoint.mark(make, id)` marks the component with
  an id: the package's name, the file's path from the package root (both from the nearest
  `rescript.json`), and the modules inside the file leading to it, as in
  `@e-cline/notes/src/Likes.res#Buttons.Like` (or `...Likes.res#` for the file's own `make`). The
  file gets `@@directive("'use weft entrypoint'")`.

An async server component is for the server renderer, which calls it once and waits for it.
Rendering one with the client reconciler would call it again on every render, each time starting a
new promise to wait for, and never finish.

The attribute is checked, so a mistake is a compile error rather than silently ignored:

- the argument is absent, `{kind: Server}` or `{kind: Entrypoint}`;
- it's on a `let` binding, or in an interface file on a `let` declaration (the only places the JSX
  transform looks), at most once, and not together with `@jsx.component`;
- only a server component may be `async`;
- a file has server components or entrypoints, not both: an entrypoint's file goes to the browser,
  and a server component's mustn't;
- an entrypoint is a binding named `make`, whose labelled arguments aren't written with function
  types (`~onSave: string => unit`, or an `option` of one): its props come from the server,
  serialized, and functions can't be. The check reads the types as written, so it can't see through
  a type alias.

In an interface file only the attribute is replaced: an async server component's signature is
already `(~id: string) => element`.

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

In its `rescript.json`, list the PPX in `ppx-flags`. The code it generates calls `WeftCore`, so
`@e-cline/weft_core` has to be among the `dependencies` (it already is if the package uses `Weft`);
this package itself isn't one:

```json
"dependencies": ["@e-cline/weft", "@e-cline/weft_core", "@e-cline/weft_dom"],
"ppx-flags": ["@e-cline/ppx_weft/ppx"]
```

An interface file declaring a `@weft.component` needs its own `@@jsxConfig` line, as with
`@jsx.component`.

## Layout

- `ppx_src/ppx_weft.ml` -- the PPX, using [ppxlib](https://github.com/ocaml-ppx/ppxlib).
- `ppx_src/bin/main.ml` -- the executable wrapping it, which is what the ReScript compiler runs.
- `ppx` -- the shell script `ppx-flags` points at; forwards to the dune-built executable.

Its tests are a package of their own, [`../weft_tests`](../weft_tests):

- `fixtures/` -- components compiled through the PPX (every kind, sync and async server components,
  entrypoints at every depth, an interface, `Weft.Jsx`). Their compiled `.res.js` is committed, so a
  change to what the PPX produces shows up in review.
- `specs/` -- the tests: shared components render exactly as their `@jsx.component` twins do, async
  server components return `Lazy` elements, entrypoints carry the right ids, assertions on the
  compiled output (the directives, the export names the client looks up), and the failing files
  below.
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
