import {makeRescriptLibConfig} from '../../../vite.config.base.ts';

// `specs/` runs in Node: the fixtures render into weft's TestRenderer,
// and the failing ones are compiled with `bsc` in a child process.
export default makeRescriptLibConfig();
