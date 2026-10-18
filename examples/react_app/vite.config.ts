import {defineConfig} from 'vite-plus';

// An ordinary Vite React app -- nothing here is ReScript-specific.
// @e-cline/react_ui_example's `Greeting` component is consumed purely through
// its built `dist/index.d.ts` + `dist/index.js` (+ `dist/Greeting.css`),
// exactly like any TSX component from any other workspace package.
export default defineConfig({});
