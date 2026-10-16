// `isDev`/`isProd` are `external`s bound to the plain string package specifier
// `@e-cline/js_env`, rather than a normal cross-package ReScript dependency
// (`dependencies` in `rescript.json`): `@e-cline/js_env` isn't a ReScript
// package, and the ReScript compiler has no notion of picking one of two files
// by build condition the way a bundler's module resolution does. The compiler
// doesn't look inside the string at all -- it just emits
// `import * as Js_env from "@e-cline/js_env"` plus `let isDev = Js_env.IS_DEV`
// into the compiled `.res.jsx` and trusts the declared types. That plain JS
// import is what a bundler's export-condition resolution (`"development"` vs.
// `"production"`, picking one of `@e-cline/js_env`'s two physical files)
// applies to, and ordinary dead-code elimination downstream of that then
// strips whatever's only reachable through `if isDev`/`if isProd`.
@module("@e-cline/js_env") external isDev: bool = "IS_DEV"
@module("@e-cline/js_env") external isProd: bool = "IS_PROD"

// `jsEnv` is `@e-cline/js_env`'s `env` constant (`'dev' | 'prod'`), viewed as a
// variant so callers can `switch` on it. `@as("dev")`/`@as("prod")` make each
// case compile to that string literal itself, so `jsEnv` is bound straight to
// `env` with no runtime mapping, and a `switch` compiles to a plain
// `jsEnv === "dev"` comparison against the imported constant -- the same
// shape as `if isDev`, so dead-code elimination removes the unreachable case
// just the same. This relies on the cases being declared with `@as`
// everywhere the type is visible (the `.resi` repeats them).
type jsEnv =
  | @as("dev") Development
  | @as("prod") Production

@module("@e-cline/js_env") external jsEnv: jsEnv = "env"
