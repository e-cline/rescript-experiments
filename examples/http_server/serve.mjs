// The same server, started from JavaScript instead of `src/Main.res`.
//
// An application made with `@e-cline/servy` is a standard fetch handler,
// `(request: Request) => Promise<Response>`, so it needs nothing from ReScript
// to run: `@hono/node-server` (or Deno, Bun, a Cloudflare Worker, ...) takes it
// as it is. Run with `vp run start:js`.
import {serve} from '@hono/node-server';

import {app} from './src/Routes.res.js';

const port = Number(process.env.PORT ?? 3000);
// This machine only, unless told otherwise: `@hono/node-server` by itself
// listens on every network interface.
const hostname = process.env.HOST ?? '127.0.0.1';

serve({fetch: app, port, hostname}, (address) => {
  console.log(`Listening on http://${address.address}:${address.port}`);
});
