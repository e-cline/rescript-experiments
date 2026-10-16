import {makeRescriptLibConfig, rootResTask} from '../../vite.config.base.ts';

export default makeRescriptLibConfig({
  tasks: {
    // Prints a few values with their generated printers.
    demo: {
      command: 'tsx src/Demo.res.jsx',
      dependsOn: [rootResTask],
      cache: false,
    },
  },
});
