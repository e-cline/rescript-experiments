// Serving a built app on Node: the client build's files, and every other request answered by the
// server build's handler.

import {createReadStream} from 'node:fs';
import {stat} from 'node:fs/promises';
import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from 'node:http';
import {extname, join, resolve, sep} from 'node:path';
import {pathToFileURL} from 'node:url';

import {getRequestListener} from '@hono/node-server';

const contentTypes: Record<string, string> = {
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.json': 'application/json',
  '.map': 'application/json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

export type BuildOptions = {
  /** The build's output directory, with `client/` and `server/index.js` in it. Default: `dist`. */
  dir?: string;
};

/** The file under `clientDir` a request's path names, if it's a file there. */
async function staticFile(
  clientDir: string,
  url: string,
): Promise<string | undefined> {
  let path: string;
  try {
    path = decodeURIComponent(new URL(url, 'http://localhost').pathname);
  } catch {
    return undefined;
  }
  // The manifest is the build's, not the app's: it isn't served.
  if (path.startsWith('/.vite/')) return undefined;
  const file = resolve(clientDir, '.' + path);
  if (!file.startsWith(clientDir + sep)) return undefined;
  try {
    return (await stat(file)).isFile() ? file : undefined;
  } catch {
    return undefined;
  }
}

/** A Node request listener for the build in `dir`. */
export async function buildListener(
  options: BuildOptions = {},
): Promise<
  (request: IncomingMessage, response: ServerResponse) => Promise<void>
> {
  const dir = resolve(options.dir ?? 'dist');
  const clientDir = join(dir, 'client');
  const module = (await import(
    pathToFileURL(join(dir, 'server', 'index.js')).href
  )) as {
    default: (request: Request) => Promise<Response>;
  };
  const handler = getRequestListener(module.default, {
    overrideGlobalObjects: false,
  });
  return async (request, response) => {
    const file =
      request.method === 'GET' || request.method === 'HEAD'
        ? await staticFile(clientDir, request.url ?? '/')
        : undefined;
    if (file === undefined) return handler(request, response);
    response.writeHead(200, {
      'Content-Type': contentTypes[extname(file)] ?? 'application/octet-stream',
      // Vite puts a hash in every name under `assets/`, so those never change.
      'Cache-Control': file.startsWith(join(clientDir, 'assets') + sep)
        ? 'public, max-age=31536000, immutable'
        : 'no-cache',
    });
    if (request.method === 'HEAD') {
      response.end();
    } else {
      createReadStream(file).pipe(response);
    }
  };
}

/** Serves the build in `dir` over HTTP, on `port` (0 for any free one) of `hostname`. */
export async function serve(
  options: BuildOptions & {port?: number; hostname?: string} = {},
): Promise<Server> {
  const listener = await buildListener(options);
  const server = createServer((request, response) => {
    listener(request, response).catch((error: unknown) => {
      console.error(error);
      if (!response.headersSent) response.writeHead(500);
      response.end();
    });
  });
  await new Promise<void>((done) =>
    server.listen(options.port ?? 3000, options.hostname ?? '127.0.0.1', done),
  );
  return server;
}
