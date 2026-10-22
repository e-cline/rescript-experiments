// What `Build_test.res` needs from files and Vite: building the app, reading what came out, and
// running the built server and chunks. The test makes the assertions.

import {readdirSync, readFileSync, rmSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

import * as Decoder from '@e-cline/weft_server/src/shared/Decoder.res.js';
import {createBuilder} from 'vite';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const app = '@e-cline/weft_split_example';

/** Builds the app with its own config, returning where the build went and its client manifest. */
export async function build(name = 'build') {
  // Under `node_modules`, so the server build finds its dependencies (`@rescript/runtime`, which a
  // server build leaves external) as it would in `dist`, without racing a `vp build` writing there.
  const outDir = join(root, `node_modules/.weft-split-${name}`);
  rmSync(outDir, {recursive: true, force: true});
  // Vite takes a build to be a production one when `NODE_ENV` is unset or `production`; Vitest sets
  // it to `test`.
  const nodeEnv = process.env.NODE_ENV;
  process.env.NODE_ENV = 'production';
  try {
    const builder = await createBuilder({
      root,
      configFile: join(root, 'vite.config.ts'),
      logLevel: 'silent',
      // Unminified, so the test can find functions by name.
      build: {outDir, minify: false},
    });
    await builder.buildApp();
  } finally {
    process.env.NODE_ENV = nodeEnv;
  }
  const clientDir = join(outDir, 'client');
  const manifest = JSON.parse(
    readFileSync(join(clientDir, '.vite/manifest.json'), 'utf8'),
  );
  const server = (
    await import(/* @vite-ignore */ join(outDir, 'server/index.js'))
  ).default;
  return {outDir, clientDir, manifest, server};
}

export function remove(built) {
  rmSync(built.outDir, {recursive: true, force: true});
}

/** The manifest's chunk for `key` (a source file's path from the root). */
export function chunk(built, key) {
  const found = built.manifest[key];
  if (found === undefined) throw new Error(`the build has no chunk for ${key}`);
  return found;
}

export const manifestKeys = (built) => Object.keys(built.manifest);

/** The manifest's entries' keys. */
export const entries = (built) =>
  Object.entries(built.manifest)
    .filter(([, found]) => found.isEntry)
    .map(([key]) => key);

/** The code of the chunk for `key`. */
export const code = (built, key) =>
  readFileSync(join(built.clientDir, chunk(built, key).file), 'utf8');

/** The files in the client build (from `dist/client`) that contain `text`. */
export function clientFilesContaining(built, text) {
  return readdirSync(built.clientDir, {recursive: true, withFileTypes: true})
    .filter((entry) => entry.isFile())
    .map((entry) => join(entry.parentPath, entry.name))
    .filter((file) => readFileSync(file, 'utf8').includes(text))
    .map((file) => file.slice(built.clientDir.length + 1));
}

export const serverCode = (built) =>
  readFileSync(join(built.outDir, 'server/index.js'), 'utf8');

/** What the built server answers a page request for `path` with. */
export async function page(built, path) {
  return (await built.server(new Request(`http://localhost${path}`))).text();
}

/**
 * Imports a built client chunk. Every entrypoint's chunk imports the bootstrap's (where the code they
 * share went), which looks for `#root` in the document when it runs: this gives it a document
 * without one, so it does nothing.
 */
function importClientChunk(file) {
  // (Under jsdom, there's a document already: without a `#root` in it.)
  globalThis.document ??= {getElementById: () => null};
  return import(/* @vite-ignore */ file);
}

/**
 * Decodes the built server's payload for `path` with the built client chunks, as the bootstrap
 * would, and returns the entrypoint files it loaded (as manifest keys).
 */
export async function loadedFor(built, path) {
  const response = await built.server(
    new Request(`http://localhost${path}`, {
      headers: {Accept: 'text/x-weft-payload'},
    }),
  );
  const loaded = [];
  const loadModule = (id) => {
    // `@e-cline/weft_split_example/src/Counter.res` is built from `src/Counter.res.js`.
    const key = id.slice(app.length + 1) + '.js';
    loaded.push(key);
    return importClientChunk(join(built.clientDir, chunk(built, key).file));
  };
  await Decoder.fromStream(Decoder.make(loadModule), response.body, undefined);
  return loaded.sort((a, b) => a.localeCompare(b));
}
