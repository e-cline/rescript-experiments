// `weft_css`'s styles: extracting them, by running their files in a module runner of the plugin's
// own; stripping their definitions from what's bundled; and the CSS modules each file's sheet is
// served as. See docs/weft_css_plan.md, section 3.

import {join} from 'node:path';

import {
  createRunnableDevEnvironment,
  createServer,
  type RunnableDevEnvironment,
  type ViteDevServer,
} from 'vite';

import type {CompiledFile} from './scan.js';

/** The environment the extraction imports style files in: Node, and nothing else runs there. */
export const cssEnvironment = 'weft_css';

/** What a module imports a sheet as: `virtual:weft/css/<sheet id>.css` (`?url`, and so on, kept). */
export const sheetPrefix = 'virtual:weft/css/';

/** A file's stylesheet, as `WeftCss.Extract` makes it. */
export type Sheet = {
  /** Its sheet id. */
  id: string;
  css: string;
  /** The other sheets its rules name (their variables or animations). */
  dependencies: string[];
};

const sheetIdPattern = /^w[0-9a-z]{6}$/;
const sheetPathPattern =
  /[\\/]node_modules[\\/]\.weft-css[\\/](w[0-9a-z]{6})\.css(?:\?.*)?$/;

/**
 * What a sheet's module resolves to: a path, under `node_modules/.weft-css`, with no file there (the
 * plugin loads its content). Vite's CSS plugin imports a module again with its own queries
 * (`?transform-only`), which a `\0` virtual id doesn't survive.
 */
export function sheetPath(root: string, id: string): string {
  return join(root, 'node_modules', '.weft-css', `${id}.css`);
}

/** The sheet id of a sheet's resolved id, if it is one. */
export function sheetOfPath(id: string): string | undefined {
  return sheetPathPattern.exec(id)?.[1];
}

/**
 * Resolves `virtual:weft/css/<id>.css` (with any query) to its path, and that path as itself; the
 * dev server's URL for it (`/node_modules/.weft-css/<id>.css`, from the root) to the path too, so
 * there's one module per sheet, whichever way it's asked for.
 */
export function resolveSheet(root: string, source: string): string | undefined {
  if (source.startsWith(sheetPrefix)) {
    const query = source.indexOf('?');
    const name = source.slice(
      sheetPrefix.length,
      query === -1 ? undefined : query,
    );
    if (!name.endsWith('.css') || !sheetIdPattern.test(name.slice(0, -4)))
      return undefined;
    return (
      sheetPath(root, name.slice(0, -4)) +
      (query === -1 ? '' : source.slice(query))
    );
  }
  if (sheetOfPath(source) === undefined) return undefined;
  return source.startsWith('/node_modules/.weft-css/') &&
    !source.startsWith(root)
    ? join(root, source)
    : source;
}

/** The functions of `Css.Internal` that `ppx_weft` writes calls of. */
const internalCalls = new Set(['class_', 'var_', 'keyframes_', 'global_']);

type Node = {type: string; start: number; end: number; [key: string]: unknown};

const isNode = (value: unknown): value is Node =>
  typeof value === 'object' &&
  value !== null &&
  typeof (value as Node).type === 'string';

/** `call`'s function's name if it's `<anything>.Internal.<one of internalCalls>`. */
function internalCall(call: Node): string | undefined {
  const callee = call.callee as Node;
  if (callee.type !== 'MemberExpression' || callee.computed) return undefined;
  const object = callee.object as Node;
  const property = callee.property as Node & {name?: string};
  if (
    object.type !== 'MemberExpression' ||
    (object.property as Node & {name?: string}).name !== 'Internal' ||
    property.name === undefined ||
    !internalCalls.has(property.name)
  ) {
    return undefined;
  }
  const [name] = call.arguments as Node[];
  return name?.type === 'Literal' &&
    typeof (name as Node & {value: unknown}).value === 'string'
    ? property.name
    : undefined;
}

/** `text`, then `code[start, end)` blanked out: spaces, but its line breaks kept. */
function blanked(code: string, start: number, end: number, text: string) {
  return text + code.slice(start + text.length, end).replace(/[^\n\r]/g, ' ');
}

/**
 * `code` with every style call replaced by its name (a string literal), and every `global_` call
 * by `void 0`, so neither the definitions nor `weft_css`'s value layer is bundled, and the module's
 * top level does nothing for them. In place, so every other position stays where it was (as the
 * directives are blanked) and no source map is needed. `parse` is Vite's (or Rolldown's) parser.
 */
export function stripStyles(
  code: string,
  parse: (code: string) => unknown,
  {inPlace = true}: {inPlace?: boolean} = {},
): string {
  const replacements: {start: number; end: number; text: string}[] = [];
  const visit = (value: unknown): void => {
    if (Array.isArray(value)) {
      for (const item of value) visit(item);
      return;
    }
    if (!isNode(value)) return;
    if (value.type === 'CallExpression') {
      const fn = internalCall(value);
      if (fn !== undefined) {
        const [name] = value.arguments as Node[];
        replacements.push({
          start: value.start,
          end: value.end,
          text:
            fn === 'global_' ? 'void 0' : code.slice(name!.start, name!.end),
        });
        return;
      }
    }
    for (const key in value) {
      if (key !== 'type' && key !== 'start' && key !== 'end') visit(value[key]);
    }
  };
  visit(parse(code));
  let stripped = '';
  let at = 0;
  for (const {start, end, text} of replacements.sort(
    (a, b) => a.start - b.start,
  )) {
    stripped +=
      code.slice(at, start) +
      (inPlace ? blanked(code, start, end, text) : text);
    at = end;
  }
  return stripped + code.slice(at);
}

/**
 * `code` without its styles' definitions (`stripStyles`, not in place): what's the same before and
 * after an edit that changed only the CSS, which needs no reload, and no refetch.
 */
export function namesOnly(
  code: string,
  parse: (code: string) => unknown,
): string {
  return stripStyles(code, parse, {inPlace: false});
}

/** The module `WeftCss.Extract` is, as an app imports it. */
const extractModule = '@e-cline/weft_css/src/shared/Extract.res.js';

type ExtractModule = {start: () => void; finish: () => Sheet[]};

export class ExtractionError extends Error {}

/**
 * Extracts the sheets of an app's style files: imports them in a module runner of its own, while
 * `WeftCss.Extract` (that runner's copy of it, so nothing else records into it) records what their
 * top levels register. One extraction at a time.
 */
export class Extractor {
  readonly sheets = new Map<string, Sheet>();
  #server: Promise<ViteDevServer> | undefined;
  #queue: Promise<unknown> = Promise.resolve();

  constructor(
    private readonly root: string,
    private readonly mode: string,
  ) {}

  #environment(): Promise<RunnableDevEnvironment> {
    this.#server ??= createServer({
      root: this.root,
      mode: this.mode,
      configFile: false,
      envFile: false,
      logLevel: 'error',
      appType: 'custom',
      server: {middlewareMode: true, hmr: false, watch: null, ws: false},
      optimizeDeps: {noDiscovery: true, include: []},
      environments: {
        [cssEnvironment]: {
          consumer: 'server',
          resolve: {
            // Its own copy of `weft_css`, and `Common.Env.isDev` as the app's build has it.
            noExternal: ['@e-cline/weft_css', '@e-cline/js_env'],
          },
          dev: {
            createEnvironment: (name, config) =>
              createRunnableDevEnvironment(name, config),
          },
        },
      },
    });
    return this.#server.then(
      (server) => server.environments[cssEnvironment] as RunnableDevEnvironment,
    );
  }

  /** Runs `task` once every extraction before it has. */
  #serially<T>(task: () => Promise<T>): Promise<T> {
    const result = this.#queue.then(task);
    this.#queue = result.catch(() => undefined);
    return result;
  }

  /**
   * Imports `files` (dropping any copy the runner has already run, so their top levels run again),
   * and gives the sheets recorded, which replace the ones of the same ids. A file whose import
   * throws fails it, saying which.
   */
  extract(files: CompiledFile[]): Promise<Sheet[]> {
    return this.#serially(async () => {
      const environment = await this.#environment();
      for (const {file} of files) {
        for (const node of environment.moduleGraph.getModulesByFile(file) ??
          []) {
          environment.moduleGraph.invalidateModule(node);
        }
        for (const node of environment.runner.evaluatedModules.getModulesByFile(
          file,
        ) ?? []) {
          environment.runner.evaluatedModules.invalidateModule(node);
        }
      }
      const extract = (await environment.runner.import(
        extractModule,
      )) as ExtractModule;
      extract.start();
      try {
        for (const compiled of files) {
          try {
            await environment.runner.import(compiled.file);
          } catch (error) {
            throw new ExtractionError(
              `[weft] couldn't extract the styles of ${compiled.id}: importing it (or a file it ` +
                `imports) threw ` +
                `${(error as Error).message}. Styles are extracted by running their file in Node, ` +
                'so a file whose top level needs the browser (or the server entry, which imports ' +
                "the plugin's virtual modules) can't have them: move them to a module of their own.",
            );
          }
        }
      } catch (error) {
        extract.finish();
        throw error;
      }
      let sheets: Sheet[];
      try {
        sheets = extract.finish();
      } catch (error) {
        throw new ExtractionError(`[weft] ${(error as Error).message}`);
      }
      for (const sheet of sheets) this.sheets.set(sheet.id, sheet);
      return sheets;
    });
  }

  /** Forgets a sheet whose file is gone, or has no styles any more. */
  forget(id: string) {
    this.sheets.delete(id);
  }

  async close() {
    const server = this.#server;
    this.#server = undefined;
    await (await server)?.close();
  }
}
