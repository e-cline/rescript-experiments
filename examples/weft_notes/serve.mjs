// Serves the build (`vp run build` first): the client's files from `dist/client`, and every other
// request answered by the server's handler. Run with `vp run start`.
import {serve} from '@e-cline/vite_plugin_weft/node';

const port = Number(process.env.PORT ?? 3000);
// This machine only, unless told otherwise.
const hostname = process.env.HOST ?? '127.0.0.1';

const server = await serve({dir: 'dist', port, hostname});
const address = server.address();
console.log(
  `Listening on http://${hostname}:${typeof address === 'object' ? address.port : port}`,
);
