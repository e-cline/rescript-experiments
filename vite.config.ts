import {defineConfig} from 'vite-plus';

// `rescript build` writes these next to their `.res`/`.resi` source (see
// vite.config.base.ts's `makeRescriptLibConfig`); both are generated,
// gitignored, and already formatted by the ReScript compiler / genType, not
// by us.
const rescriptGeneratedPatterns = ['**/*.res.jsx', '**/*.gen.tsx'];

export default defineConfig({
  run: {
    tasks: {
      // The one place ReScript is compiled, for the whole workspace.
      // `rescript build` run from here follows the root `rescript.json`'s
      // `dependencies` (every `packages/*` package) and compiles them,
      // plus the ReScript dependencies they share (`rescript-vitest`,
      // `@rescript/webapi`, ...), in a single process. Every ReScript
      // package's `build`/`test`/`typecheck` depends on this task by name
      // (`rootResTask` in vite.config.base.ts) instead of defining its own
      // `res` task: per-package `rescript build`s that `vp run -r` runs in
      // parallel each compile those shared dependencies in place under
      // `node_modules`, racing on the same `lib/` and intermittently
      // failing with "Corrupted compiled interface". `input`/`output` cover
      // every package so the cache invalidates when any package's sources
      // change. Run it alone with `vp run -w res`.
      //
      // Not cached: it also writes compiled output for shared dependencies
      // under `node_modules` (e.g. `rescript-vitest`'s `Vitest.res.jsx`),
      // which a cache replay doesn't restore after `clean` + `install` wipe
      // it, leaving tests failing with "Cannot find package
      // 'rescript-vitest/src/Vitest.res.jsx'". `rescript build` is
      // incremental, so re-running it is cheap.
      //
      // Depends on building the `@prettyPrint` PPX (tools/ppx/pretty_print,
      // an OCaml program built by dune): `rescript build` runs it on every
      // file of each package listing it in `ppx-flags`, so its executable
      // has to exist first.
      res: {
        command: 'rescript build',
        dependsOn: ['@e-cline/ppx_pretty_print#build'],
        cache: false,
      },
      // Watches the whole workspace; not a `dependsOn` of anything, since a
      // `-w` process never exits (see RESCRIPT.md). Run with
      // `vp run -w res:watch`.
      'res:watch': {
        command: 'rescript build -w',
        cache: false,
      },
    },
  },
  // What the pre-commit hook (`.vite-hooks/pre-commit`, which runs
  // `vp staged`) does to staged files: format and lint whatever Vite+
  // handles, and format ReScript sources with the compiler's own formatter.
  staged: {
    '*.{js,jsx,mjs,ts,tsx,json,md,yaml,yml,css,html}': 'vp check --fix',
    '*.{res,resi}': 'rescript format',
  },
  fmt: {
    ignorePatterns: [...rescriptGeneratedPatterns],
    printWidth: 80,
    tabWidth: 2,
    useTabs: false,
    embeddedLanguageFormatting: 'auto',
    singleQuote: true,
    semi: true,
    quoteProps: 'preserve',
    bracketSpacing: false,
    sortImports: true,
    trailingComma: 'all',
    proseWrap: 'always', // Wraps markdown
    // jsdoc: true, // jsdoc formatting
    overrides: [
      {
        files: ['**/*.md'],
        options: {
          printWidth: 100,
        },
      },
    ],
  },
  lint: {
    ignorePatterns: ['dist/**', ...rescriptGeneratedPatterns],
    options: {
      typeAware: true,
      typeCheck: true,
    },
    overrides: [
      {
        // `res-bench`'s tests use Node's own test runner, whose `describe`
        // and `it` return promises that the runner itself waits for.
        files: ['tools/benchmarking/cli/*.test.ts'],
        rules: {'typescript/no-floating-promises': 'off'},
      },
    ],
  },
});
