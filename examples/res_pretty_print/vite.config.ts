import {makeRescriptLibConfig, rootResTask} from '../../vite.config.base.ts';

export default makeRescriptLibConfig({
  tasks: {
    // Prints a few values with their generated printers.
    demo: {
      command: 'node src/Demo.res.js',
      dependsOn: [rootResTask],
      cache: false,
    },
  },
});
