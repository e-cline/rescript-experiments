import {makeRescriptLibConfig, rootResTask} from '../../vite.config.base.ts';

export default makeRescriptLibConfig({
  tasks: {
    // Runs the server (on $PORT, default 3000) until interrupted.
    start: {
      command: 'tsx src/Main.res.jsx',
      dependsOn: [rootResTask],
      cache: false,
    },
    // The same server, started from JavaScript (`serve.mjs`).
    'start:js': {
      command: 'tsx serve.mjs',
      dependsOn: [rootResTask],
      cache: false,
    },
  },
});
