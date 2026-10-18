import {makeRescriptLibConfig} from '../../vite.config.base.ts';

// Server and client run in one process here (tier 1 of the plan's tests):
// the client renders into weft_core's TestRenderer, so no DOM is needed.
export default makeRescriptLibConfig();
