import {makeLibConfig} from '../../vite.config.base.ts';

// The build and dev tests run Vite on fixture apps, which takes longer than a unit test.
export default makeLibConfig({testTimeout: 30_000});
