import {weft} from '@e-cline/weft_vite_plugin';

import {makeRescriptLibConfig, rootResTask} from '../../vite.config.base.ts';

// The root `res` task compiles `src/*.res` (through ppx_weft) to `src/*.res.js`, which the plugin
// serves and bundles. The tests (`tests/Notes_test.res`) run the app through the plugin's harness:
// the server in a worker, the pages in jsdom.
export default makeRescriptLibConfig({
  plugins: [weft({server: 'src/Server.res.js'})],
  testEnvironment: 'jsdom',
  testTimeout: 60_000,
  tasks: {
    build: {
      command: 'vp build',
      dependsOn: [{task: 'build', from: 'dependencies'}, rootResTask],
    },
    dev: {
      command: 'vp dev',
      dependsOn: [{task: 'build', from: 'dependencies'}, rootResTask],
      cache: false,
    },
    start: {
      command: 'node serve.mjs',
      dependsOn: ['build'],
      cache: false,
    },
    // The browser tests (`e2e/`), against the build: they need Chromium (`playwright install`).
    e2e: {
      command: 'playwright test -c e2e/playwright.config.ts',
      dependsOn: ['build'],
      cache: false,
    },
  },
});
