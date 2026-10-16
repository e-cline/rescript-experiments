/***
Whether the current build is a development or production build. Exactly one of
`isDev`/`isProd` is `true`.

Both are bound to the constants exported by `@e-cline/js_env`, whose
`package.json` export conditions (`"development"` / `"production"`) let a bundler
pick a literal-valued file at bundle time, so dead-code elimination can remove
whichever branch the literal makes unreachable. See this package's README
("Debug-only assertions") for why this has to be a plain string-specifier binding
rather than a normal ReScript package dependency.
*/

/** `true` in a development build, `false` in a production build. */
let isDev: bool

/** `true` in a production build, `false` in a development build. */
let isProd: bool

/**
The build's environment as a variant, for use with `switch`. Bound to
`@e-cline/js_env`'s `env` (`'dev' | 'prod'`), with each case backed by that
string (`Production` is `"prod"`), so a `switch` on `jsEnv` tree-shakes exactly
like an `if` on `isDev`/`isProd`.
*/
type jsEnv =
  | @as("dev") Development
  | @as("prod") Production

/** `Development` in a development build, `Production` in a production build. */
let jsEnv: jsEnv
