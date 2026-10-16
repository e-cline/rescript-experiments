/***
Exercises the `@module("@e-cline/js_env")` bindings in `Env.res` directly.
Which concrete constants `@e-cline/js_env`'s own `package.json` `exports`
resolves to (`true`/`false` vs. `false`/`true`) is a bundler/runtime
concern -- not something a test running inside this package should
exercise (see `@e-cline/js_env`'s own `env.test.ts`, which tests its two
variants directly by file for the same reason). The only thing to check
here is that `isDev` and `isProd` come through as real, opposite booleans
no matter which variant a given test run happens to resolve.
*/

open Vitest

describe("Env", () => {
  test("isDev and isProd are opposite booleans", t => {
    t->expect(Env.isDev)->Expect.toBe(!Env.isProd)
  })

  test("jsEnv agrees with isDev and isProd", t => {
    t->expect(Env.jsEnv == Env.Development)->Expect.toBe(Env.isDev)
    t->expect(Env.jsEnv == Env.Production)->Expect.toBe(Env.isProd)
  })
})
