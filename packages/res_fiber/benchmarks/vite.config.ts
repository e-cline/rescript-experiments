import {defineConfig} from 'vite-plus';

import {rootResTask} from '../../../vite.config.base.ts';

// The benchmarks are ReScript (`src/Main.res`), compiled to `src/Main.res.jsx`
// by the root-level `res` task (see ../../../vite.config.ts). `build` bundles
// that output, together with the `@e-cline/res_fiber` and `@rescript/runtime`
// modules it imports, into a single minified `dist/bench.js`, so that the
// `bench` task measures the code a consumer's production build would run
// rather than the compiler's unbundled output.
export default defineConfig({
  build: {
    minify: 'terser',
    terserOptions: {
      // Mangling doesn't change how fast the code runs, and unmangled names
      // keep CPU profiles of the bundle readable.
      mangle: false,
      compress: {
        // Note: It seems like Terser needs 2 passes to remove unused branches.
        passes: 2,
      },
    },
    lib: {
      formats: ['es'],
      // Named explicitly so the bundle is `dist/bench.js`, not `dist/Main.res.js`.
      entry: {bench: './src/Main.res.jsx'},
    },
    rolldownOptions: {
      // The harness is loaded from `node_modules` at run time rather than
      // bundled: only the code being measured should go through the minifier.
      external: ['mitata'],
    },
  },
  run: {
    tasks: {
      build: {
        command: 'vp build',
        dependsOn: [{task: 'build', from: 'dependencies'}, rootResTask],
      },
      cleanbuild: {
        command: 'rm -rf ./dist',
        cache: false,
      },
      // `--expose-gc` lets mitata collect garbage between benchmarks, so one
      // benchmark's garbage isn't collected during the next.
      bench: {
        command: 'node --expose-gc ./dist/bench.js',
        dependsOn: ['build'],
        cache: false,
      },
      // Checks that the bundle still runs under `res-bench` (see
      // tools/benchmarking's README): lists its benchmarks and measures one.
      // Quick, and saves nothing, so `vp run test` can run it.
      test: {
        command: 'res-bench check',
        dependsOn: ['build'],
        cache: false,
      },
      // The same benchmarks in several fresh processes, summarized and saved
      // (see tools/benchmarking's README).
      'bench:record': {
        command: 'res-bench run',
        dependsOn: ['build'],
        cache: false,
      },
      // This package's benchmarks at a git ref against the working tree's (or
      // another ref's), alternating between the two.
      'bench:compare': {
        command: 'res-bench compare',
        dependsOn: ['build'],
        cache: false,
      },
      // Fills the `<!-- res-bench -->` tables in the README from the
      // newest recording `bench:record` saved (see tools/benchmarking's README).
      'bench:readme': {
        command: 'res-bench readme README.md',
        cache: false,
      },
      // Bundle sizes, minified and compressed, of the apps in `size/` and of
      // examples/res_fiber_app (see the README). Builds nothing to disk.
      size: {
        command: 'tsx ./size/size.ts',
        dependsOn: [rootResTask],
        cache: false,
      },
      // Type-checks `size/size.ts`, the only TypeScript here.
      typecheck: {
        command: 'tsc --noEmit',
        cache: false,
      },
      // The same benchmarks, run straight from the compiler's output, to see
      // what bundling and minifying change. Node won't load a `.jsx` file by
      // itself, hence `tsx`, which transforms each module separately and
      // doesn't minify.
      'bench:unbundled': {
        command: 'node --expose-gc --import tsx ./src/Main.res.jsx',
        dependsOn: [rootResTask],
        cache: false,
      },
    },
  },
});
