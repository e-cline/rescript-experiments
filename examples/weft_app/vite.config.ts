import {weftCss} from '@e-cline/weft_vite_plugin';

import {makeRescriptLibConfig, rootResTask} from '../../vite.config.base.ts';

// A Vite app whose source is ReScript: the root `res` task compiles `src/*.res` to `src/*.res.js`,
// which `index.html` loads. `weftCss()` extracts the styles in `src/Styles.res` into the bundle's
// CSS. The tests render the app into jsdom.
export default makeRescriptLibConfig({
  plugins: [weftCss()],
  testEnvironment: 'jsdom',
  tasks: {
    build: {
      command: 'vp build',
      dependsOn: [{task: 'build', from: 'dependencies'}, rootResTask],
    },
    dev: {
      command: 'vp dev',
      dependsOn: [rootResTask],
      cache: false,
    },
  },
});
