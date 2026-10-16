import {defineConfig} from 'vite-plus';

// This is the default (see https://vitest.dev/config/#include).
// We also use it for `typecheck.include`.
const testFileMatch = ['**/*.{test,spec}.?(c|m)[jt]s?(x)'];

// Matches ReScript-compiled test files (e.g. `Point_test.res` -> the
// `Point_test.res.jsx` `rescript build` writes next to it in `tests/`) for
// `makeRescriptLibConfig`'s `test.include`. Deliberately `_test`/`_spec`,
// not the `.test`/`.spec` dot-infix `testFileMatch` above uses: ReScript
// derives a file's module name from its filename with only the first
// letter capitalized, so `point.test.res` becomes module `Point.test` --
// which collides with an actual `Point` module in the same directory
// (ReScript treats the dot as nesting a submodule under it) and fails to
// compile with "The module or file Point can't be found". Since a test
// file's name matching the module it tests is the whole point, `_test`
// side-steps this entirely: `Point_test.res` becomes module `Point_test`,
// which cannot collide with `Point` no matter what it tests.
const resTestFileMatch = ['**/*_{test,spec}.res.jsx'];

// Every ReScript package is compiled by the single root-level `res` task (see
// `vite.config.ts`): `rescript build` run from the workspace root compiles all
// packages, and the dependencies they share (e.g. `rescript-vitest`), in one
// process. Per-package `rescript build`s run in parallel by `vp run -r` raced
// on those shared dependencies' `lib/` and intermittently failed with
// "Corrupted compiled interface".
export const rootResTask = '@e-cline/res-experiments#res';

/** A `run.tasks` entry, as `makeRescriptLibConfig`'s `tasks` option takes. */
export type RunTask = {
  command: string | string[];
  dependsOn?: (string | {task: string; from: 'dependencies'})[];
  cache?: boolean;
};

/**
 * Base Vite+ config for a library package.
 *
 * Also defines the `run.tasks` every one of those packages used to duplicate as
 * near-identical `package.json` scripts: `build` (bundle `src/`, via `vp
 * pack`), `build:watch`, `cleanbuild`, `test`, `test:watch`, `typecheck` (`tsc
 * --noEmit`), and `typecheck:watch`. Every task other than `cleanbuild` depends
 * on its workspace dependencies' own `build` task (transitively), since each
 * resolves sibling packages the normal Node way -- through their built `dist/`
 * via `exports`, not source -- so `vp run -r <task>` needs that ordering
 * instead of relying on `pnpm -r`'s topological sort; `build` also depends on
 * its own `typecheck` so a type error fails the build. `cleanbuild` and every
 * `:watch` task disable caching: `cleanbuild` is destructive rather than
 * producing a cacheable output, and the `:watch` tasks run indefinitely rather
 * than completing with a single result to cache. `typecheck` also disables
 * caching -- unlike `build`'s output, `tsc --noEmit` has no build artifact to
 * key a cache hit off of, and its diagnostics can depend on sibling files
 * outside `test.include`/`pack.entry`'s cache inputs.
 */
export function makeLibConfig(): ReturnType<typeof defineConfig> {
  return defineConfig({
    run: {
      tasks: {
        build: {
          command: 'vp pack',
          dependsOn: [{task: 'build', from: 'dependencies'}, 'typecheck'],
        },
        'build:watch': {
          command: 'vp pack --watch',
          dependsOn: [{task: 'build', from: 'dependencies'}],
          cache: false,
        },
        cleanbuild: {
          command: 'rm -rf ./dist',
          cache: false,
        },
        test: {
          command: 'vp test run',
          dependsOn: [{task: 'pack', from: 'dependencies'}],
        },
        'test:watch': {
          command: 'vp test watch',
          dependsOn: [{task: 'build', from: 'dependencies'}],
          cache: false,
        },
        typecheck: {
          command: 'tsc --noEmit',
          dependsOn: [{task: 'build', from: 'dependencies'}],
          cache: false,
        },
        'typecheck:watch': {
          command: 'tsc --watch',
          dependsOn: [{task: 'build', from: 'dependencies'}],
          cache: false,
        },
      },
    },
    pack: {
      entry: [
        'src/**/*.ts',
        '!src/**/internal/**',
        '!src/**/testing/**',
        '!src/**/tests/**',
        '!src/**/__tests__/**',
        '!src/**/*.test.*',
        '!src/**/*.md', // Skip markdown files
      ],
      format: ['es'],
      dts: {
        tsgo: true,
      },
      minify: false,
      unbundle: true,
      deps: {neverBundle: true},
      fixedExtension: false,
    },
    test: {
      include: [...testFileMatch],
      // The shared `test` task runs here even for packages with no test
      // files yet -- don't fail those.
      passWithNoTests: true,
      typecheck: {
        enabled: true,
        include: [...testFileMatch],
      },
    },
  });
}

/**
 * Base Vite+ config for a library package authored in ReScript (`.res`/
 * `.resi` under `src/`, compiled in-source via the `rescript` CLI) rather
 * than directly in TypeScript.
 *
 * Layers a dependency on the root-level `res` task (`rescript build`, defined
 * in the root `vite.config.ts`; see {@linkcode rootResTask}) on top of
 * {@linkcode makeLibConfig}, and makes `build`, `test`, and `typecheck`
 * depend on it. The package has no `res` task of its own. That's the whole
 * integration: ReScript's own compiler already emits plain ESM
 * (`*.res.jsx`, via `"suffix": ".res.jsx"` in `rescript.json`) colocated
 * with the `.res` source, so Vite/Vitest resolve it like any other `.js`
 * file with no bundler plugin needed, and genType's `*.gen.tsx` output is
 * itself a normal `.tsx` file, so `vp pack`'s `tsgo`-driven `dts` pass and
 * `tsc --noEmit` type-check it like any other TypeScript entry. The
 * package's own `src/index.ts` re-exports from the `.gen.tsx` file(s) it
 * cares about, keeping `pack.entry: 'src/index.ts'` the same as every other
 * library package -- ReScript is an implementation detail of `src/`, not a
 * different build shape.
 *
 * A package using this needs `"allowJs": true` in its own `tsconfig.json`
 * (`.gen.tsx` imports the compiled `*.res.jsx` sibling, which has no
 * `.d.ts` of its own -- the import resolves to `any`, which is fine because
 * genType's own type annotations in the same file are what consumers
 * actually see) and must list `rescript` (plus any ReScript libraries it
 * uses, e.g. `@rescript/react`) in `devDependencies` so `node_modules/.bin`
 * has it.
 *
 * The root-level `res:watch` (`rescript build -w`) is provided for local dev but
 * deliberately isn't wired into `dependsOn` anywhere: a `-w` process never
 * exits, and `dependsOn` means "finish before starting," so depending on it
 * would deadlock. Run it in its own terminal alongside `vp run test:watch`
 * / `vp run build:watch` -- Vite/Vitest already watch the whole package
 * directory, so they pick up the `.res.jsx`/`.gen.tsx` files it rewrites on
 * every save without any extra wiring.
 *
 * Packages with a TypeScript entry point (`src/index.ts`) must pass
 * `typescriptSurface: true`; the default (`false`) is for packages consumed only
 * from other ReScript code or run as ReScript programs. Extra tasks like
 * `start`/`demo` go in `tasks`.
 *
 * Tests can be written directly in ReScript (e.g. with
 * [`rescript-vitest`](https://github.com/cometkim/rescript-vitest)) instead
 * of TypeScript: `test.include` here also matches `*_test.res.jsx` /
 * `*_spec.res.jsx` -- the compiled output of e.g. `Point_test.res` -- so
 * Vitest picks them up the same way it picks up `.test.ts` files. Name
 * these `<Module>_test.res`, not `<module>.test.res` -- see
 * `resTestFileMatch`'s own comment for why the underscore matters. Nothing
 * else is required; a ReScript test file is just a `.res` module that
 * happens to call a test-runner library instead of exporting anything.
 */
export function makeRescriptLibConfig(
  options: {
    /**
     * Whether the package hands a typed surface to TypeScript (a
     * `src/index.ts` that `vp pack` bundles and `tsc` checks). Pass `true`
     * for those packages. When `false`, the package exists purely to be
     * consumed from other ReScript code (or to run as a ReScript program):
     * there is nothing for `vp pack`/`tsc` to do, so `build` and `typecheck`
     * become no-ops that still wait on the root `res` task, the `pack` config
     * is omitted, and tests aren't type-checked. They stay defined so
     * `vp run -r build`/`typecheck` from the repo root needn't special-case
     * the package. Default: `false`.
     */
    typescriptSurface?: boolean;
    /**
     * Extra `run.tasks` merged over the standard ones (e.g. `start`/`demo`
     * tasks that run a compiled `*.res.jsx` entry point).
     */
    tasks?: Record<string, RunTask>;
  } = {},
): ReturnType<typeof defineConfig> {
  const typescriptSurface = options.typescriptSurface ?? false;
  const noSurface = (verb: string) =>
    `echo "No TypeScript surface to ${verb} -- see the root res task"`;

  return defineConfig({
    run: {
      tasks: {
        build: {
          command: typescriptSurface ? 'vp pack' : noSurface('build'),
          dependsOn: [
            {task: 'build', from: 'dependencies'},
            ...(typescriptSurface ? ['typecheck'] : []),
            rootResTask,
          ],
        },
        ...(typescriptSurface && {
          'build:watch': {
            command: 'vp pack --watch',
            dependsOn: [{task: 'build', from: 'dependencies'}],
            cache: false,
          },
          cleanbuild: {
            command: 'rm -rf ./dist',
            cache: false,
          },
        }),
        test: {
          command: 'vp test run',
          dependsOn: [{task: 'build', from: 'dependencies'}, rootResTask],
        },
        'test:watch': {
          command: 'vp test watch',
          dependsOn: [{task: 'build', from: 'dependencies'}, rootResTask],
          cache: false,
        },
        typecheck: {
          command: typescriptSurface ? 'tsc --noEmit' : noSurface('typecheck'),
          dependsOn: [{task: 'build', from: 'dependencies'}, rootResTask],
          cache: typescriptSurface ? false : undefined,
        },
        ...(typescriptSurface && {
          'typecheck:watch': {
            command: 'tsc --watch',
            dependsOn: [{task: 'build', from: 'dependencies'}],
            cache: false,
          },
        }),
        ...options.tasks,
      },
    },
    ...(typescriptSurface && {
      pack: {
        entry: [
          'src/**/*.ts',
          '!src/**/internal/**',
          '!src/**/testing/**',
          '!src/**/tests/**',
          '!src/**/__tests__/**',
          '!src/**/*.test.*',
          '!src/**/*.md',
        ],
        format: ['es' as const],
        dts: {
          tsgo: true,
        },
        minify: false,
        unbundle: true,
        deps: {neverBundle: true},
        fixedExtension: false,
      },
    }),
    test: {
      include: [...testFileMatch, ...resTestFileMatch],
      // `rescript build` mirrors every compiled file (including compiled
      // test files) into `lib/bs/src/` as part of its own build cache;
      // without this, Vitest's `resTestFileMatch` pattern above matches
      // both copies and runs every ReScript-authored test twice. The first
      // two entries are Vitest's own default `exclude` (`defaultExclude`
      // in `vitest/config`) -- specifying `exclude` at all replaces that
      // default rather than adding to it, so they're repeated here.
      exclude: ['**/node_modules/**', '**/.git/**', 'lib/**'],
      passWithNoTests: true,
      typecheck: {
        enabled: typescriptSurface,
        include: [...testFileMatch],
      },
    },
  });
}
