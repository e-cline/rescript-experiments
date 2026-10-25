import {makeRescriptLibConfig} from '../../vite.config.base.ts';

// The components' tests render them with the HTML renderer (as a server would) and into a jsdom
// document (as a browser would).
export default makeRescriptLibConfig({testEnvironment: 'jsdom'});
