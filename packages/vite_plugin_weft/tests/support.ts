import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  realpathSync,
  rmSync,
  symlinkSync,
} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

import type {InlineConfig} from 'vite';

import {weft, type Options} from '../src/index.js';

/**
 * The fixture apps: ReScript packages in the workspace, compiled through ppx_weft by the root
 * `res` task (see `fixtures/README.md`).
 */
export const fixtures = resolve(
  dirname(fileURLToPath(import.meta.url)),
  'fixtures',
);

/** A fixture's package name. */
export const fixtureName = (fixture: string) =>
  `@e-cline/vite_plugin_weft_fixture_${fixture}`;

const copies: string[] = [];

/** Links `copy/node_modules` to the same packages as `original/node_modules`. */
function linkDependencies(original: string, copy: string) {
  const from = join(original, 'node_modules');
  const add = (name: string) => {
    const path = join(copy, 'node_modules', name);
    mkdirSync(dirname(path), {recursive: true});
    symlinkSync(realpathSync(join(from, name)), path, 'dir');
  };
  for (const entry of readdirSync(from)) {
    if (entry.startsWith('.')) continue;
    if (entry.startsWith('@')) {
      for (const inner of readdirSync(join(from, entry)))
        add(`${entry}/${inner}`);
    } else {
      add(entry);
    }
  }
}

/**
 * A copy of the fixture `name` in a temporary directory, which a test can build into or change.
 * Its compiled files are the ones the root build wrote; its `node_modules` links to the same
 * packages as the fixture's, the other fixtures (`widgets`) included.
 */
export function copyFixture(name: string): string {
  const original = join(fixtures, name);
  const root = realpathSync(mkdtempSync(join(tmpdir(), `weft-${name}-`)));
  copies.push(root);
  cpSync(original, root, {
    recursive: true,
    // ReScript's build cache, and the links made below.
    filter: (source) =>
      !['node_modules', 'lib', 'dist'].includes(basename(source)) ||
      dirname(source) !== original,
  });
  linkDependencies(original, root);
  return root;
}

/** Removes every copy `copyFixture` made. */
export function removeCopies() {
  for (const copy of copies.splice(0)) {
    rmSync(copy, {recursive: true, force: true});
  }
}

export const defaultOptions: Options = {
  server: 'src/Server.res.js',
  client: 'src/Client.res.js',
};

/** A Vite config for the app at `root` with the plugin, and no config file. */
export function config(
  root: string,
  options: Partial<Options> = {},
): InlineConfig {
  return {
    root,
    configFile: false,
    logLevel: 'silent',
    plugins: [weft({...defaultOptions, ...options})],
    // Dependency optimisation would reload the page when it finds a new dependency, which the dev
    // tests would see as one of the plugin's reloads.
    optimizeDeps: {noDiscovery: true, include: []},
  };
}
