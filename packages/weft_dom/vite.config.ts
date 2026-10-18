import {makeRescriptLibConfig} from '../../vite.config.base.ts';

// The renderer's tests render into a real (jsdom) document.
export default makeRescriptLibConfig({testEnvironment: 'jsdom'});
