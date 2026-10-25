import {weft} from '@e-cline/weft_vite_plugin';

import {makeRescriptLibConfig, rootResTask} from '../../vite.config.base.ts';

// The root `res` task compiles `src/**/*.res` (through ppx_weft) to `src/**/*.res.js`, which the
// plugin serves and bundles. The tests (`tests/*_test.res`) open the pages through the plugin's
// harness: the server in a worker, the pages in jsdom.
export default makeRescriptLibConfig({
  plugins: [weft({server: 'src/server/Server.res.js'})],
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
  },
});
