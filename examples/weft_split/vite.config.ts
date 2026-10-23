import {weft} from '@e-cline/vite_plugin_weft';

import {makeRescriptLibConfig, rootResTask} from '../../vite.config.base.ts';

// The root `res` task compiles `src/*.res` (through ppx_weft) to `src/*.res.js`, which the plugin
// bundles: the client's build to `dist/client`, the server's to `dist/server/index.js`. The build
// test (`tests/Build_test.res`) builds the app itself, into its `node_modules`; the harness tests
// (`tests/Source_test.res`, `tests/Built_test.res`) open its pages through the plugin's harness.
export default makeRescriptLibConfig({
  plugins: [weft({server: 'src/Server.res.js'})],
  // The harness tests open pages in jsdom.
  testEnvironment: 'jsdom',
  // The build tests build the whole app.
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
  },
});
