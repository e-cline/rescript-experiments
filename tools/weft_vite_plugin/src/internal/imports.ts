// Which stylesheets each entrypoint file's code imports: a walk over the static imports of the
// compiled files, from the entrypoint file. The same in development and in a build, and before
// either has built anything. (Dynamic imports aren't followed: what a lazily loaded module renders
// comes with its own chunk.)

import {readFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';

import {parseAst} from 'vite';

import type {Scan} from './scan.js';

type Node = {type: string; source?: {value?: unknown}};

/** The specifiers `code` statically imports (and re-exports from). */
function staticImports(code: string): string[] {
  const program = parseAst(code) as unknown as {body: Node[]};
  return program.body.flatMap((node) =>
    (node.type === 'ImportDeclaration' ||
      node.type === 'ExportNamedDeclaration' ||
      node.type === 'ExportAllDeclaration') &&
    typeof node.source?.value === 'string'
      ? [node.source.value]
      : [],
  );
}

/**
 * The compiled file a specifier in `from` names, if it's one of the scanned packages' (ReScript
 * imports another package's file as `<package name>/<path>`, its own as `./<path>`).
 */
function resolveImport(
  scanned: Scan,
  from: string,
  specifier: string,
): string | undefined {
  if (!specifier.endsWith(scanned.suffix)) return undefined;
  if (specifier.startsWith('.')) return resolve(dirname(from), specifier);
  for (const pkg of scanned.packages) {
    if (specifier.startsWith(`${pkg.name}/`)) {
      return join(pkg.dir, specifier.slice(pkg.name.length + 1));
    }
  }
  return undefined;
}

/** Each entrypoint file's sheets (those of every style file its code imports), by file id. */
export function entrypointSheets(
  scanned: Scan,
  read: (file: string) => string = (file) => readFileSync(file, 'utf8'),
): Record<string, string[]> {
  const importsOf = new Map<string, string[]>();
  const imported = (file: string): string[] => {
    let found = importsOf.get(file);
    if (found === undefined) {
      let code: string;
      try {
        code = read(file);
      } catch {
        code = '';
      }
      found = staticImports(code).flatMap((specifier) => {
        const target = resolveImport(scanned, file, specifier);
        return target === undefined ? [] : [target];
      });
      importsOf.set(file, found);
    }
    return found;
  };
  const result: Record<string, string[]> = {};
  for (const entry of scanned.files.values()) {
    if (entry.kind !== 'entrypoint') continue;
    const sheets: string[] = [];
    const seen = new Set<string>();
    const visit = (file: string) => {
      if (seen.has(file)) return;
      seen.add(file);
      for (const next of imported(file)) visit(next);
      // After its imports': a sheet comes after the ones it may depend on.
      const sheet = scanned.files.get(file)?.sheet;
      if (sheet !== undefined) sheets.push(sheet);
    };
    visit(entry.file);
    if (sheets.length > 0) result[entry.id] = sheets;
  }
  return result;
}
