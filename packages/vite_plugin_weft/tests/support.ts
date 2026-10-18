import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  rmSync,
  symlinkSync,
} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

import type {InlineConfig} from 'vite';

import {weft, type Options} from '../src/index.js';

const fixtures = resolve(dirname(fileURLToPath(import.meta.url)), 'fixtures');

/** `@e-cline/js_env`'s directory: `@e-cline/common` depends on it. */
const jsEnv = realpathSync(
  resolve(fixtures, '../../../common/node_modules/@e-cline/js_env'),
);

const copies: string[] = [];

/**
 * A copy of the fixture `name` in a temporary directory, with a `node_modules` linking its
 * dependencies: `widgets/` as `@fixtures/widgets`, and `@e-cline/js_env`.
 */
export function copyFixture(name: string): string {
  const root = realpathSync(mkdtempSync(join(tmpdir(), `weft-${name}-`)));
  copies.push(root);
  cpSync(join(fixtures, name), root, {recursive: true});
  const link = (packageName: string, target: string) => {
    const path = join(root, 'node_modules', packageName);
    mkdirSync(dirname(path), {recursive: true});
    symlinkSync(target, path, 'dir');
  };
  link('@fixtures/widgets', join(root, 'widgets'));
  link('@e-cline/js_env', jsEnv);
  return root;
}

/** Removes every copy `copyFixture` made. */
export function removeCopies() {
  for (const copy of copies.splice(0))
    rmSync(copy, {recursive: true, force: true});
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
  };
}
