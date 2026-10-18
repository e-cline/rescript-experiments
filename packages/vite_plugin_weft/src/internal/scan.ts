// Finding the entrypoint files: every compiled file with the `'use weft entrypoint'` directive in the
// app's ReScript sources and its ReScript dependencies'. `rescript build` has written them all before
// Vite starts, so this is a walk over directories, not a build.

import {
  existsSync,
  readdirSync,
  readFileSync,
  realpathSync,
  statSync,
} from 'node:fs';
import {dirname, join, relative, sep} from 'node:path';

import {findDirective, type Kind} from './directives.js';

/** What the plugin needs from a `rescript.json`. */
type RescriptJson = {
  name?: string;
  sources?: Source | Source[];
  dependencies?: string[];
  suffix?: string;
  'ppx-flags'?: (string | string[])[];
};

type Source =
  | string
  | {dir: string; subdirs?: boolean | Source[]; type?: string};

export type Package = {
  /** The `name` in its `rescript.json`, which entrypoint ids start with. */
  name: string;
  /** Its directory, symlinks resolved. */
  dir: string;
  config: RescriptJson;
};

export type CompiledFile = {
  /** The id `ppx_weft` gives it: its package's name, then its source's path in the package. */
  id: string;
  /** Its absolute path. */
  file: string;
  kind: Kind;
};

export class ScanError extends Error {}

export function readRescriptJson(dir: string): RescriptJson {
  const path = join(dir, 'rescript.json');
  try {
    return JSON.parse(readFileSync(path, 'utf8')) as RescriptJson;
  } catch (error) {
    throw new ScanError(
      `[weft] couldn't read ${path}: ${(error as Error).message}`,
    );
  }
}

/** The directory of the package `name`, as Node (and ReScript) would find it from `from`. */
function findDependency(name: string, from: string): string | undefined {
  for (let dir = from; ; dir = dirname(dir)) {
    const candidate = join(dir, 'node_modules', name);
    if (existsSync(join(candidate, 'rescript.json')))
      return realpathSync(candidate);
    if (dirname(dir) === dir) return undefined;
  }
}

/** The app's ReScript package and its ReScript dependencies, transitively (not dev dependencies). */
export function findPackages(root: string): Package[] {
  const packages = new Map<string, Package>();
  const visit = (dir: string) => {
    if (packages.has(dir)) return;
    const config = readRescriptJson(dir);
    if (config.name === undefined) {
      throw new ScanError(`[weft] ${join(dir, 'rescript.json')} has no "name"`);
    }
    packages.set(dir, {name: config.name, dir, config});
    for (const name of config.dependencies ?? []) {
      const found = findDependency(name, dir);
      if (found === undefined) {
        throw new ScanError(
          `[weft] couldn't find ${name}, a dependency in ${join(dir, 'rescript.json')}`,
        );
      }
      visit(found);
    }
  };
  visit(realpathSync(root));
  return [...packages.values()];
}

/** The directories a package's `sources` name, dev sources left out. */
function sourceDirs(
  dir: string,
  sources: Source | Source[] | undefined,
): string[] {
  const dirs: string[] = [];
  const add = (base: string, source: Source) => {
    if (typeof source === 'string') {
      dirs.push(join(base, source));
      return;
    }
    if (source.type === 'dev') return;
    const sourceDir = join(base, source.dir);
    dirs.push(sourceDir);
    if (source.subdirs === true) {
      dirs.push(...subdirectories(sourceDir));
    } else if (Array.isArray(source.subdirs)) {
      for (const inner of source.subdirs) add(sourceDir, inner);
    }
  };
  for (const source of [sources ?? []].flat()) add(dir, source);
  return dirs;
}

function subdirectories(dir: string): string[] {
  const found: string[] = [];
  for (const entry of readdirSync(dir, {withFileTypes: true})) {
    if (
      entry.isDirectory() &&
      entry.name !== 'node_modules' &&
      !entry.name.startsWith('.')
    ) {
      const inner = join(dir, entry.name);
      found.push(inner, ...subdirectories(inner));
    }
  }
  return found;
}

const toPosix = (path: string) => path.split(sep).join('/');

/** The id `ppx_weft` gives the file compiled to `file`, which is in `pkg`. */
export function fileId(pkg: Package, file: string, suffix: string): string {
  const source = file.slice(0, -suffix.length) + '.res';
  return `${pkg.name}/${toPosix(relative(pkg.dir, source))}`;
}

/** The ids the marks in an entrypoint file name (`Entrypoint.mark(make, "<id>")`), file part only. */
export function markedFileIds(code: string): string[] {
  const ids = new Set<string>();
  for (const match of code.matchAll(
    /\.mark\(\s*[\w$]+\s*,\s*"([^"#]*)#[^"]*"\s*\)/g,
  )) {
    ids.add(match[1]!);
  }
  return [...ids];
}

/** Reads `file`, if it has a Weft directive, as one of the files the plugin cares about. */
export function readCompiledFile(
  pkg: Package,
  file: string,
  suffix: string,
  code = readFileSync(file, 'utf8'),
): CompiledFile | undefined {
  const directive = findDirective(code);
  if (directive === undefined) return undefined;
  const id = fileId(pkg, file, suffix);
  if (directive.kind === 'entrypoint') {
    // The client loads the file by the id the server writes, which is the PPX's: if the two were
    // ever made differently, every entrypoint in the file would fail to load, so fail here instead.
    for (const marked of markedFileIds(code)) {
      if (marked !== id) {
        throw new ScanError(
          `[weft] ${file} marks an entrypoint as being in ${marked}, but its id is ${id}. ` +
            'Was it compiled with a different rescript.json?',
        );
      }
    }
  }
  return {id, file, kind: directive.kind};
}

export type Scan = {
  /** The suffix compiled files have (`suffix` in the app's `rescript.json`). */
  suffix: string;
  packages: Package[];
  /** The source directories scanned (each package's, dev sources left out). */
  dirs: Set<string>;
  /** Every file with a Weft directive, by absolute path. */
  files: Map<string, CompiledFile>;
};

/** The suffix the app's compiled files have. */
export function suffixOf(root: string): string {
  return readRescriptJson(root).suffix ?? '.res.js';
}

export function scan(root: string): Scan {
  const suffix = suffixOf(root);
  const packages = findPackages(root);
  const dirs = new Set<string>();
  const files = new Map<string, CompiledFile>();
  for (const pkg of packages) {
    for (const dir of sourceDirs(pkg.dir, pkg.config.sources)) {
      if (!existsSync(dir) || !statSync(dir).isDirectory()) continue;
      dirs.add(dir);
      for (const entry of readdirSync(dir, {withFileTypes: true})) {
        if (!entry.isFile() || !entry.name.endsWith(suffix)) continue;
        const file = join(dir, entry.name);
        const compiled = readCompiledFile(pkg, file, suffix);
        if (compiled !== undefined) files.set(file, compiled);
      }
    }
  }
  return {suffix, packages, dirs, files};
}

/** The package `file` is in, if it's one of the scanned packages' (the deepest, if they nest). */
export function packageOf(scanned: Scan, file: string): Package | undefined {
  let found: Package | undefined;
  for (const pkg of scanned.packages) {
    if (
      file.startsWith(pkg.dir + sep) &&
      (found === undefined || pkg.dir.length > found.dir.length)
    ) {
      found = pkg;
    }
  }
  return found;
}

/** The entrypoint files, sorted by id (so generated code doesn't depend on the order of a walk). */
export function entrypoints(scanned: Scan): CompiledFile[] {
  return [...scanned.files.values()]
    .filter((file) => file.kind === 'entrypoint')
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

/** Whether the app's `rescript.json` runs `ppx_weft`, without which `@weft.component` does nothing. */
export function hasPpx(root: string): boolean {
  return (readRescriptJson(root)['ppx-flags'] ?? [])
    .flat()
    .some((flag) => flag.includes('ppx_weft'));
}
