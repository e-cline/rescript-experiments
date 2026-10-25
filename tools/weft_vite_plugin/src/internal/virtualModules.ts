// The code of the plugin's virtual modules.

import {relative, sep} from 'node:path';

import {sheetPath, sheetPrefix, type Sheet} from './css.js';
import {replaceStylesheet} from './replaceStylesheet.js';
import type {CompiledFile} from './scan.js';

export const clientReferencesId = 'virtual:weft/client-references';
export const clientId = 'virtual:weft/client';
export const bootstrapId = 'virtual:weft/bootstrap';
export const assetsId = 'virtual:weft/assets';
export const ssrReferencesId = 'virtual:weft/ssr-references';
export const sheetsId = 'virtual:weft/sheets';

/** The custom HMR event that tells the client to refetch the page (a server-only file changed). */
export const refreshEvent = 'weft:refresh';

/** The custom HMR event that tells the client a sheet's CSS changed (only its CSS: no reload). */
export const cssEvent = 'weft:css';

/**
 * `virtual:weft/client-references`: each entrypoint file's id, and a function importing it. Each
 * `import()` is a chunk of its own. This is the only way the client loads an entrypoint, so a server
 * can't make it load anything else. `virtual:weft/ssr-references` is the same map for the server,
 * which decodes the page's payload to render its HTML (`WeftServer.Page`).
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

/** The module of the entrypoint file \`id\`, as \`WeftServer.Decoder.make\`'s \`loadModule\` takes. */
export function loadModule(id) {
  return Object.hasOwn(modules, id)
    ? modules[id]()
    : Promise.reject(new Error(\`[weft] \${id} isn't an entrypoint file\`));
}
`;
}

/**
 * `virtual:weft/ssr-references`: the same map, for the server, which loads them all up front
 * (statically: a server has no use for a chunk per file, and server code imports some of them
 * anyway, to render them).
 */
export function ssrReferencesCode(files: CompiledFile[]): string {
  const imports = files.map(
    ({file}, index) =>
      `import * as module${index} from ${JSON.stringify(file)};`,
  );
  const lines = files.map(
    ({id}, index) => `  ${JSON.stringify(id)}: module${index},`,
  );
  return `${imports.join('\n')}

const modules = {
${lines.join('\n')}
};

export default modules;

/** The module of the entrypoint file \`id\`, as \`WeftServer.Decoder.make\`'s \`loadModule\` takes. */
export function loadModule(id) {
  return Object.hasOwn(modules, id)
    ? Promise.resolve(modules[id])
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

export ${replaceStylesheet.toString()}

if (import.meta.hot) {
  import.meta.hot.on(${JSON.stringify(refreshEvent)}, (data) => {
    for (const listener of listeners) listener(data);
  });
  import.meta.hot.on(${JSON.stringify(cssEvent)}, ({href}) => replaceStylesheet(href));
}
`;
}

/**
 * `virtual:weft/bootstrap`: the default bootstrap, for an app that doesn't give one.
 * `WeftServer.Bootstrap.main` reads the first page's rows and renders them into `#root`, and goes on
 * from there (navigation, and refetching when a server file changes in development).
 */
export function bootstrapCode(): string {
  return `import {loadModule, onRefresh} from ${JSON.stringify(clientId)};
import {main} from "@e-cline/weft_server/src/client/Bootstrap.res.js";

main(loadModule, onRefresh);
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
  /** Each stylesheet (`weft_css`'s), by sheet id: its URL, and the sheets its rules name. */
  sheets: Record<string, {href: string; dependencies: string[]}>;
  /** Each entrypoint file's stylesheets (those its code imports), by id. */
  entrypointSheets: Record<string, string[]>;
};

/**
 * `virtual:weft/sheets`, an entry of the client build of its own: it imports every sheet with
 * `?url`, so each is emitted as an asset of its own (processed by Vite's CSS pipeline), whose URL
 * the server's assets then read from the manifest. Nothing loads it.
 */
export function sheetsCode(sheets: string[]): string {
  const imports = sheets.map(
    (id, index) =>
      `import sheet${index} from ${JSON.stringify(`${sheetPrefix}${id}.css?url`)};`,
  );
  return `${imports.join('\n')}

export default {${sheets.map((id, index) => `${JSON.stringify(id)}: sheet${index}`).join(', ')}};
`;
}

/**
 * `virtual:weft/assets`: the assets, and the server's `loadModule` (from
 * `virtual:weft/ssr-references`), with which `WeftServer.Page` renders a page's HTML.
 */
export function assetsCode(assets: Assets): string {
  return `import {loadModule} from ${JSON.stringify(ssrReferencesId)};

export default {...${JSON.stringify(assets, null, 2)}, loadModule};
`;
}

const toPosix = (path: string) => path.split(sep).join('/');

/** The URL the dev server serves `file` at. */
export function devUrl(root: string, base: string, file: string): string {
  // A virtual module, as Vite serves one.
  if (file.startsWith('\0')) return `${base}@id/__x00__${file.slice(1)}`;
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
  sheets: Sheet[] = [],
  entrypointSheets: Record<string, string[]> = {},
): Assets {
  return {
    scripts: [`${base}@vite/client`, devUrl(root, base, bootstrap)],
    preloads: [],
    styles: [],
    entrypoints: Object.fromEntries(
      files.map(({id, file}) => [id, [devUrl(root, base, file)]]),
    ),
    sheets: Object.fromEntries(
      sheets.map(({id, dependencies}) => [
        id,
        {href: devUrl(root, base, sheetPath(root, id)), dependencies},
      ]),
    ),
    entrypointSheets,
  };
}

/** A chunk in a client build's `.vite/manifest.json`, as much as is used here. */
export type ManifestChunk = {
  file: string;
  name?: string;
  src?: string;
  imports?: string[];
  css?: string[];
  isEntry?: boolean;
  isDynamicEntry?: boolean;
};

export type Manifest = Record<string, ManifestChunk>;

export class ManifestError extends Error {}

/** A file's key in the manifest: its path from the root. */
export function manifestKey(root: string, file: string): string {
  // A virtual module is in the manifest by its name.
  if (file.startsWith('\0')) return file.slice(1);
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

/** The file a sheet was emitted as, from the client build's manifest. */
function sheetFile(manifest: Manifest, id: string): string {
  const suffix = `.weft-css/${id}.css`;
  for (const [key, chunk] of Object.entries(manifest)) {
    if (key.endsWith(suffix) || chunk.src?.endsWith(suffix)) return chunk.file;
  }
  throw new ManifestError(`[weft] the client build has no stylesheet ${id}`);
}

export function buildAssets(
  manifest: Manifest,
  root: string,
  base: string,
  bootstrap: string,
  files: CompiledFile[],
  sheets: Sheet[] = [],
  entrypointSheets: Record<string, string[]> = {},
): Assets {
  const url = (file: string) => base + file;
  const client = closure(manifest, manifestKey(root, bootstrap));
  return {
    sheets: Object.fromEntries(
      sheets.map(({id, dependencies}) => [
        id,
        {href: url(sheetFile(manifest, id)), dependencies},
      ]),
    ),
    entrypointSheets,
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
