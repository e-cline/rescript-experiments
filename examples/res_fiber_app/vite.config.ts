import {makeRescriptLibConfig, rootResTask} from '../../vite.config.base.ts';

// A Vite app whose source is ReScript: the root `res` task compiles `src/*.res` to `src/*.res.jsx`,
// which `index.html` loads. The tests render the app into jsdom.
export default makeRescriptLibConfig({
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
