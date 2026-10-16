import {defineConfig} from 'vite-plus';

import {rootResTask} from '../../vite.config.base.ts';

// The app's source is ReScript (`src/Main.res`), compiled to
// `src/Main.res.jsx` by the root-level `res` task (see ../../vite.config.ts);
// Vite bundles that output like any other JavaScript. Only `tests/test.ts`
// is TypeScript, and it is a Node script run against the built bundle, not
// part of the app.
export default defineConfig({
  build: {
    minify: 'terser',
    terserOptions: {
      mangle: false,
      compress: {
        // Note: It seems like Terser needs 2 passes to remove unused branches.
        passes: 2,
      },
    },
    lib: {
      formats: ['es'],
      // Named explicitly so the bundle is `dist/main.js`, not `dist/Main.res.js`.
      entry: {main: './src/Main.res.jsx'},
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
      test: {
        command: 'tsx ./tests/test.ts',
        dependsOn: ['build'],
        cache: false,
      },
      typecheck: {
        command: 'tsc --noEmit',
        cache: false,
      },
    },
  },
});
