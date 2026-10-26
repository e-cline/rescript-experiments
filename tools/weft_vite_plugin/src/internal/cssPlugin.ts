// The Vite plugin for `weft_css`'s styles, which `weft()` includes and `weftCss()` is, for an app
// without a server: it finds the style files, extracts their sheets, strips the definitions from
// every environment's modules, and serves each sheet as a CSS module.

import {readFileSync} from 'node:fs';
import {dirname, join} from 'node:path';

import {
  parseAst,
  type Plugin,
  type ResolvedConfig,
  type ViteDevServer,
} from 'vite';

import {
  Extractor,
  namesOnly,
  type Sheet,
  resolveSheet,
  sheetOfPath,
  sheetPath,
  sheetPrefix,
  stripStyles,
} from './css.js';
import {findDirectives} from './directives.js';
import {dynamicImports, sheetWalker} from './imports.js';
import {
  hasPpx,
  packageOf,
  readCompiledFile,
  readRescriptJson,
  scan,
  styleFiles,
  type CompiledFile,
  type Scan,
} from './scan.js';
import {cssEvent, devUrl} from './virtualModules.js';

type Change = {
  /**
   * Whether only the file's CSS changed: it's a style file, its sheet's CSS is different, and its
   * code without its definitions is the same.
   */
  cssOnly: boolean;
  /**
   * The sheets whose CSS is different: the file's, and those of the style files that import it (at
   * any depth), whose definitions may use what it exports.
   */
  changed: string[];
};

export type CssPluginOptions = {
  /**
   * Whether each style file, in a client environment, imports its sheet, so Vite's own CSS
   * handling loads it with the module's chunk (an app without a server). `weft()` sends sheets
   * itself, so its client modules don't.
   */
  importSheets: boolean;
  /**
   * The environment the app's server runs in, if it has one (`weft()`'s): every other one runs
   * client code (the browser's, the server-side render's of client components, a test's). Without
   * it, a client environment is one whose consumer is the client.
   */
  serverEnvironment?: string;
  /** The app's scan, if another plugin keeps it (`weft()`); otherwise this one scans. */
  scanned?: () => Scan;
  /** Scans again, if another plugin keeps the scan. */
  rescan?: () => void;
  /** Called in development when a sheet came, went, or changed what it depends on. */
  onChange?: () => void;
};

/** The plugin, and the sheets it extracted, for `weft()`'s assets. */
export type CssPlugin = {
  plugin: Plugin;
  /** Every style file's sheet, once extracted. */
  sheets: () => Promise<Sheet[]>;
};

/** `WeftCss.Sheets`, as an app imports it. */
const sheetsModule = '@e-cline/weft_css/src/client/Sheets.res.js';

/** Blanks out a file's `'use weft css'` directive, leaving any others for `weft()`. */
function blankCssDirective(code: string): string {
  const found = findDirectives(code);
  let blanked = code;
  for (const {kind, start, end} of found?.directives ?? []) {
    if (kind === 'css') {
      blanked =
        blanked.slice(0, start) + ' '.repeat(end - start) + blanked.slice(end);
    }
  }
  return blanked;
}

export function cssPlugin(options: CssPluginOptions): CssPlugin {
  let config: ResolvedConfig;
  let ownScan: Scan | undefined;
  let extractor: Extractor | undefined;
  /** The extraction of every style file, once per build, or once a dev server's started. */
  let extracted: Promise<unknown> | undefined;
  let devServer: ViteDevServer | undefined;
  /** Each style file's code without its definitions (`namesOnly`), as it was last transformed. */
  const lastNames = new Map<string, string>();
  /**
   * The change being handled to each file: each environment's `hotUpdate` asks, and they all get
   * the one answer (the extraction it does runs once). By file, since changes to several are handled
   * at once (ReScript writes a copy of each compiled file in its `lib/`, too).
   */
  const handling = new Map<
    string,
    {code: string; change: Promise<Change | undefined>}
  >();

  const scanned = () => options.scanned?.() ?? ownScan!;
  const rescan = () => {
    if (options.rescan !== undefined) options.rescan();
    else ownScan = scan(config.root);
  };

  /**
   * Extracts every style file's sheet, the first time it's asked for (for this build). In
   * development, one that fails is tried again the next time, once the file's fixed.
   */
  const extractAll = () => {
    extracted ??= (async () => {
      extractor ??= new Extractor(config.root, config.mode);
      const files = styleFiles(scanned());
      // An app with no styles may not have weft_css at all: nothing to run.
      if (files.length > 0) await extractor.extract(files);
      if (config.command === 'build') {
        // Nothing changes during a build: the runner isn't needed again.
        await extractor.close();
      }
    })().catch((error: unknown) => {
      if (config.command === 'serve') extracted = undefined;
      throw error;
    });
    return extracted;
  };

  /**
   * What a compiled file's change is to its styles: rescanned if it gained or lost them; its sheet,
   * and those of the style files importing it, extracted again; and whether only its CSS changed
   * (its code without its definitions is as it was). `undefined` if neither it nor any file
   * importing it has styles, or nothing's extracted yet.
   */
  const handle = (file: string, type: string): Promise<Change | undefined> => {
    const current = scanned();
    const pkg = packageOf(current, file);
    if (
      !file.endsWith(current.suffix) ||
      pkg === undefined ||
      !current.dirs.has(dirname(file))
    ) {
      return Promise.resolve(undefined);
    }
    let code = '';
    try {
      if (type !== 'delete') code = readFileSync(file, 'utf8');
    } catch {}
    const handled = handling.get(file);
    if (handled?.code === code) return handled.change;
    const change = (async (): Promise<Change | undefined> => {
      if (extractor === undefined) return undefined;
      const was = current.files.get(file);
      const now: CompiledFile | undefined =
        type === 'delete'
          ? undefined
          : readCompiledFile(pkg, file, current.suffix, code);
      if (
        was?.sheet !== now?.sheet ||
        (was === undefined) !== (now === undefined)
      ) {
        rescan();
      }
      if (was?.sheet !== undefined && now?.sheet === undefined) {
        extractor.forget(was.sheet);
        options.onChange?.();
      }
      // The style files whose definitions may use what it exports (the extraction ran them).
      const importers = (await extractor.importersOf(file)).flatMap(
        (importer) => {
          const found = scanned().files.get(importer);
          return found?.sheet === undefined ? [] : [found];
        },
      );
      const files = now?.sheet === undefined ? importers : [now, ...importers];
      if (files.length === 0) return undefined;
      await extractAll();
      const before = new Map(
        files.map(({sheet}) => [sheet!, extractor!.sheets.get(sheet!)]),
      );
      await extractor.extract(files);
      const changed: string[] = [];
      for (const [sheet, was] of before) {
        const after = extractor.sheets.get(sheet);
        if (after?.dependencies.join() !== was?.dependencies.join()) {
          options.onChange?.();
        }
        if (after?.css !== was?.css) changed.push(sheet);
      }
      // The sheets' modules load again, with the new CSS, whoever asks for them next.
      for (const sheet of changed) {
        for (const environment of Object.values(
          devServer?.environments ?? {},
        )) {
          for (const node of environment.moduleGraph.getModulesByFile(
            sheetPath(config.root, sheet),
          ) ?? []) {
            environment.moduleGraph.invalidateModule(node);
          }
        }
      }
      if (now?.sheet === undefined) return {cssOnly: false, changed};
      const names = lastNames.get(file);
      const nowNames = namesOnly(code, parseAst);
      lastNames.set(file, nowNames);
      return {
        // (A file written again unchanged, as for a dependency's change, is handled as it always
        // was: only a change to the CSS alone skips the reload or refetch.)
        cssOnly:
          changed.includes(now.sheet) &&
          was?.sheet === now.sheet &&
          names === nowNames,
        changed,
      };
    })();
    handling.set(file, {code, change});
    return change;
  };

  /**
   * `code` (the app's compiled `file`, for a client environment that doesn't import sheets:
   * `weft()`'s) with each `import()` of one of its compiled files resolving once that file's sheets
   * have loaded too: those of every style file it imports (at any depth), and the sheets those
   * depend on. So whatever renders the code it loads is styled. (An entrypoint's sheets come with
   * the rows that use it instead, and Weft's own `import()`s of entrypoints aren't the app's code.)
   * `undefined` if there's none to wait for. The sheets' URLs are the server's: in development
   * written in (a `?url` import of one is empty outside the browser's environment, in a test's), in
   * a build imported (`?url`, for the hashed file). Those imports, and the helper, are at the end, so
   * no line moves.
   */
  const waitingForSheets = async (
    code: string,
    file: string,
  ): Promise<string | undefined> => {
    const imports = dynamicImports(scanned(), file, code);
    if (imports.length === 0) return undefined;
    await extractAll();
    const walk = sheetWalker(scanned());
    const urls: string[] = [];
    let rewritten = '';
    let at = 0;
    for (const {start, end, file: target} of imports.sort(
      (a, b) => a.start - b.start,
    )) {
      // Those a sheet depends on before it (two may depend on each other).
      const sheets: string[] = [];
      const seen = new Set<string>();
      const add = (id: string) => {
        if (seen.has(id)) return;
        seen.add(id);
        for (const dependency of extractor?.sheets.get(id)?.dependencies ??
          []) {
          add(dependency);
        }
        sheets.push(id);
      };
      for (const id of walk(target)) add(id);
      if (sheets.length === 0) continue;
      // In development, each sheet's URL as the server has it; in a build, the asset's (hashed).
      const names = sheets.map((id) => {
        if (config.command === 'serve') {
          return JSON.stringify(
            devUrl(config.root, config.base, sheetPath(config.root, id)),
          );
        }
        if (!urls.includes(id)) urls.push(id);
        return `__weftSheet${urls.indexOf(id)}`;
      });
      rewritten +=
        code.slice(at, start) +
        `__weftImport(${code.slice(start, end)}, [${names.join(', ')}])`;
      at = end;
    }
    if (at === 0) return undefined;
    const tail =
      urls
        .map(
          (id, index) =>
            `import __weftSheet${index} from ${JSON.stringify(`${sheetPrefix}${id}.css?url`)};`,
        )
        .join('') +
      `import {load as __weftLoadSheet} from ${JSON.stringify(sheetsModule)};` +
      'function __weftImport(module, sheets) { return Promise.all([module, ...sheets.map(__weftLoadSheet)]).then((loaded) => loaded[0]); }';
    return `${rewritten}${code.slice(at)}\n${tail}\n`;
  };

  const plugin: Plugin = {
    name: 'weft:css',

    configResolved(resolved) {
      config = resolved;
      if (options.scanned === undefined) {
        const dependencies = readRescriptJson(config.root).dependencies ?? [];
        if (
          dependencies.includes('@e-cline/weft_css') &&
          !hasPpx(config.root)
        ) {
          throw new Error(
            `[weft] ${join(config.root, 'rescript.json')} doesn't run ppx_weft: add ` +
              '"@e-cline/ppx_weft/ppx" to its "ppx-flags". Without it, weft_css\'s styles have no ' +
              'names, and `Css.class` throws when its file is loaded.',
          );
        }
        ownScan = scan(config.root);
      }
    },

    async buildStart() {
      if (this.environment.mode !== 'build') return;
      // A build is run after `rescript build`, which may have changed which files have styles.
      if (extracted === undefined && options.scanned === undefined) rescan();
      // Failing early: a definition that throws stops the build here.
      await extractAll();
    },

    configureServer(server) {
      devServer = server;
    },

    resolveId(source) {
      return resolveSheet(config.root, source);
    },

    async load(id) {
      const sheet = sheetOfPath(id);
      if (sheet === undefined) return undefined;
      await extractAll();
      const found = extractor!.sheets.get(sheet);
      if (found === undefined) {
        this.error(`[weft] no file has styles whose sheet id is ${sheet}`);
      }
      return found.css;
    },

    transform: {
      filter: {code: ['use weft css', 'import(']},
      async handler(code, id) {
        const file = id.split('?')[0]!;
        const client =
          options.serverEnvironment === undefined
            ? this.environment.config.consumer === 'client'
            : this.environment.name !== options.serverEnvironment;
        let result: string | undefined;
        if (findDirectives(code)?.css === true) {
          result = blankCssDirective(stripStyles(code, parseAst));
          lastNames.set(file, namesOnly(code, parseAst));
          const sheet = scanned().files.get(file)?.sheet;
          if (options.importSheets && sheet !== undefined && client) {
            // On the first line, which was the directive: every other line stays where it was.
            result = `import ${JSON.stringify(`${sheetPrefix}${sheet}.css`)};${result}`;
          }
        }
        const current = scanned();
        if (
          !options.importSheets &&
          client &&
          file.endsWith(current.suffix) &&
          current.dirs.has(dirname(file))
        ) {
          result = (await waitingForSheets(result ?? code, file)) ?? result;
        }
        return result === undefined ? undefined : {code: result, map: null};
      },
    },

    async hotUpdate({file, type}) {
      const change = await handle(file, type);
      if (change === undefined) return undefined;
      // When only the CSS changed, the module's code is the same, so nothing reloads or refetches
      // (this plugin is before `weft()`'s, whose `hotUpdate` then has no modules to act on).
      // Otherwise the change is handled as usual, and the sheets that changed are updated too (a
      // refetch's rows name sheets the page has loaded already).
      const usual = change.cssOnly ? [] : undefined;
      if (this.environment.name !== 'client') return usual;
      if (options.importSheets) {
        // Each sheet is a CSS module the client imports: Vite's own CSS update applies it. (A change
        // to code reloads the page, which loads the sheets again.)
        if (!change.cssOnly) return undefined;
        return change.changed.flatMap((sheet) => [
          ...(this.environment.moduleGraph.getModulesByFile(
            sheetPath(config.root, sheet),
          ) ?? []),
        ]);
      }
      // The page links them: the client swaps each link for a fresh one (`virtual:weft/client`).
      for (const sheet of change.changed) {
        this.environment.hot.send({
          type: 'custom',
          event: cssEvent,
          data: {
            id: sheet,
            href: devUrl(
              config.root,
              config.base,
              sheetPath(config.root, sheet),
            ),
          },
        });
      }
      return usual;
    },

    async closeBundle() {
      // In development, when the server closes.
      if (config.command === 'serve') await extractor?.close();
    },
  };

  return {
    plugin,
    sheets: async () => {
      await extractAll();
      return [...(extractor?.sheets.values() ?? [])].sort((a, b) =>
        a.id < b.id ? -1 : a.id > b.id ? 1 : 0,
      );
    },
  };
}
