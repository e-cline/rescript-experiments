// The code of the plugin's virtual modules.

import {relative, sep} from 'node:path';

import type {CompiledFile} from './scan.js';

export const clientReferencesId = 'virtual:weft/client-references';
export const clientId = 'virtual:weft/client';
export const assetsId = 'virtual:weft/assets';

/** The custom HMR event that tells the client to refetch the page (a server-only file changed). */
export const refreshEvent = 'weft:refresh';

/**
 * `virtual:weft/client-references`: each entrypoint file's id, and a function importing it. Each
 * `import()` is a chunk of its own. This is the only way the client loads an entrypoint, so a server
 * can't make it load anything else.
 */
export function clientReferencesCode(files: CompiledFile[]): string {
  const lines = files.map(
    ({id, file}) =>
      `  ${JSON.stringify(id)}: () => import(${JSON.stringify(file)}),`,
  );
  return `const modules = {
${lines.join('\n')}
};

export default modules;

/** The module of the entrypoint file \`id\`, as \`WeftServer.Client.make\`'s \`loadModule\` takes. */
export function loadModule(id) {
  return Object.hasOwn(modules, id)
    ? modules[id]()
    : Promise.reject(new Error(\`[weft] \${id} isn't an entrypoint file\`));
}
`;
}

/** `virtual:weft/client`: what a bootstrap needs from the plugin. */
export function clientCode(): string {
  return `export {loadModule} from ${JSON.stringify(clientReferencesId)};

const listeners = new Set();

/**
 * Calls \`listener\` whenever a file only the server uses has changed in development (so the page's
 * payload should be fetched again). Returns a function that stops it.
 */
export function onRefresh(listener) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

if (import.meta.hot) {
  import.meta.hot.on(${JSON.stringify(refreshEvent)}, (data) => {
    for (const listener of listeners) listener(data);
  });
}
`;
}

/** What a page needs to load the client: `virtual:weft/assets`' default export. */
export type Assets = {
  /** The module scripts to load, in order: in development, Vite's client and then the bootstrap. */
  scripts: string[];
  /** The chunks the bootstrap imports, for `modulepreload` links. */
  preloads: string[];
  /** The stylesheets the bootstrap imports. */
  styles: string[];
  /** For each entrypoint file, by id: its chunk, then the chunks it imports. */
  entrypoints: Record<string, string[]>;
};

export function assetsCode(assets: Assets): string {
  return `export default ${JSON.stringify(assets, null, 2)};\n`;
}

const toPosix = (path: string) => path.split(sep).join('/');

/** The URL the dev server serves `file` at. */
export function devUrl(root: string, base: string, file: string): string {
  const path = relative(root, file);
  return path.startsWith('..') || path === file
    ? `${base}@fs${toPosix(file).replace(/^(?!\/)/, '/')}`
    : `${base}${toPosix(path)}`;
}

export function devAssets(
  root: string,
  base: string,
  bootstrap: string,
  files: CompiledFile[],
): Assets {
  return {
    scripts: [`${base}@vite/client`, devUrl(root, base, bootstrap)],
    preloads: [],
    styles: [],
    entrypoints: Object.fromEntries(
      files.map(({id, file}) => [id, [devUrl(root, base, file)]]),
    ),
  };
}

/** A chunk in a client build's `.vite/manifest.json`, as much as is used here. */
export type ManifestChunk = {
  file: string;
  imports?: string[];
  css?: string[];
  isEntry?: boolean;
  isDynamicEntry?: boolean;
};

export type Manifest = Record<string, ManifestChunk>;

export class ManifestError extends Error {}

/** A file's key in the manifest: its path from the root. */
export function manifestKey(root: string, file: string): string {
  return toPosix(relative(root, file));
}

/** `key`'s chunk, then every chunk it imports, directly or not, and the stylesheets of them all. */
function closure(
  manifest: Manifest,
  key: string,
): {files: string[]; css: string[]} {
  const files: string[] = [];
  const css = new Set<string>();
  const seen = new Set<string>();
  const visit = (key: string) => {
    if (seen.has(key)) return;
    seen.add(key);
    const chunk = manifest[key];
    if (chunk === undefined)
      throw new ManifestError(
        `[weft] the client build has no chunk for ${key}`,
      );
    files.push(chunk.file);
    for (const file of chunk.css ?? []) css.add(file);
    for (const imported of chunk.imports ?? []) visit(imported);
  };
  visit(key);
  return {files, css: [...css]};
}

export function buildAssets(
  manifest: Manifest,
  root: string,
  base: string,
  bootstrap: string,
  files: CompiledFile[],
): Assets {
  const url = (file: string) => base + file;
  const client = closure(manifest, manifestKey(root, bootstrap));
  return {
    scripts: [url(client.files[0]!)],
    preloads: client.files.slice(1).map(url),
    styles: client.css.map(url),
    entrypoints: Object.fromEntries(
      files.map(({id, file}) => [
        id,
        closure(manifest, manifestKey(root, file)).files.map(url),
      ]),
    ),
  };
}
