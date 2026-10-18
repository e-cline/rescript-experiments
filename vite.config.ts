import {defineConfig} from 'vite-plus';

// `rescript build` writes these next to their `.res`/`.resi` source (see
// vite.config.base.ts's `makeRescriptLibConfig`): `.res.js`, or `.res.jsx` in a
// package with preserved JSX, plus genType's `.gen.tsx`. All are generated (the JS is
// committed; `.gen.tsx` is gitignored) and already formatted by the ReScript
// compiler / genType, not by us.
const rescriptGeneratedPatterns = [
  '**/*.res.js',
  '**/*.res.jsx',
  '**/*.gen.tsx',
];

export default defineConfig({
  run: {
    tasks: {
      // The one place ReScript is compiled, for every package but those with
      // preserved JSX. `rescript build` run from here follows the root
      // `rescript.json`'s `dependencies` (every such package) and compiles
      // them to `.res.js` (any JSX lowered to function calls),
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
      // under `node_modules` (e.g. `rescript-vitest`'s `Vitest.res.js`),
      // which a cache replay doesn't restore after `clean` + `install` wipe
      // it, leaving tests failing with "Cannot find package
      // 'rescript-vitest/src/Vitest.res.js'". `rescript build` is
      // incremental, so re-running it is cheap.
      //
      // Packages with preserved JSX are separate ReScript build roots with their own
      // `res` task, which depends on this one (`jsx`, `package-specs`, and
      // `suffix` are root-only settings; see vite.config.base.ts's
      // `makeRescriptLibConfig`).
      //
      // Depends on building the PPXs (tools/ppx/*, OCaml programs built by
      // dune): `rescript build` runs each on every file of each package
      // listing it in `ppx-flags`, so their executables have to exist first.
      res: {
        command: 'rescript build',
        dependsOn: [
          '@e-cline/ppx_pretty_print#build',
          '@e-cline/ppx_weft#build',
        ],
        cache: false,
      },
      // The opam switch every PPX builds with (tools/ppx/setup.sh; see
      // tools/ppx/README.md). Each PPX's `build` depends on this, so the
      // switch is set up once per run, never by two builds at once. Not
      // cached: it checks the switch on this machine, which no cache
      // describes, and does nothing when it's already in sync.
      'ppx:setup': {
        command: 'tools/ppx/setup.sh',
        cache: false,
      },
      // Watches the whole workspace; not a `dependsOn` of anything, since a
      // `-w` process never exits (see RESCRIPT.md). Run with
      // `vp run -w res:watch`.
      'res:watch': {
        command: 'rescript build -w',
        cache: false,
      },
      // Format, check the formatting of, and clean the packages this root
      // builds. The root `fmt`/`check`/`rescript:clean` scripts run these
      // with `vp run -r`, which also reaches the preserved-JSX packages' own copies.
      'res:fmt': {command: 'rescript format', cache: false},
      'res:check': {command: 'rescript format --check', cache: false},
      'res:clean': {command: 'rescript clean', cache: false},
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
