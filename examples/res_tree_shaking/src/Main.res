/***
An ordinary Vite app whose source is written in ReScript, consuming @e-cline/res_common's `Env`
module as a normal ReScript package dependency (see `rescript.json`). `rescript build` compiles this
file to plain ESM (`Main.res.js`), which Vite bundles like any other JavaScript -- no bundler
plugin. The compiled file imports `isDev`/`isProd` from `@e-cline/res_common/src/Env.res.js`, which
itself binds to @e-cline/js_env's `IS_DEV`/`IS_PROD`, so building this example for production is the
real end-to-end test of whether that whole chain (js_env's export condition -> Env.res's binding ->
this file's `if`) actually gets dead-code-eliminated, not just something asserted from ReScript unit
tests. See ./tests/test.ts for the assertions against the built output.
*/

type result = {isDev: bool, isProd: bool}

let main = () => {
  let isDev = ResCommon.Env.isDev
  let isProd = ResCommon.Env.isProd

  // Expect: tree-shaken (isDev is false in a production build).
  if isDev {
    Console.log("[env:isDev]")
  }

  // Expect: NOT tree-shaken (isProd is true in a production build).
  if isProd {
    Console.log("[env:isProd]")
  }

  // Same checks, through the `Env.jsEnv` variant instead of the two booleans.
  switch ResCommon.Env.jsEnv {
  // Expect: tree-shaken.
  | Development => Console.log("[env:jsEnv:Development]")
  // Expect: NOT tree-shaken.
  | Production => Console.log("[env:jsEnv:Production]")
  }

  {isDev, isProd}
}

let mainResult = main()
