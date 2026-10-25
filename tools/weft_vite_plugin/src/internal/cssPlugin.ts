// The Vite plugin for `weft_css`'s styles, which `weft()` includes and `weftCss()` is, for an app
// without a server: it finds the style files, extracts their sheets, strips the definitions from
// every environment's modules, and serves each sheet as a CSS module.

import {dirname, join} from 'node:path';

import {parseAst, type Plugin, type ResolvedConfig} from 'vite';

import {
  Extractor,
  type Sheet,
  resolveSheet,
  sheetOfPath,
  sheetPath,
  sheetPrefix,
  stripStyles,
} from './css.js';
import {findDirectives} from './directives.js';
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

export type CssPluginOptions = {
  /**
   * Whether each style file, in a client environment, imports its sheet, so Vite's own CSS
   * handling loads it with the module's chunk (an app without a server). `weft()` sends sheets
   * itself, so its client modules don't.
   */
  importSheets: boolean;
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

  const scanned = () => options.scanned?.() ?? ownScan!;
  const rescan = () => {
    if (options.rescan !== undefined) options.rescan();
    else ownScan = scan(config.root);
  };

  /** Extracts every style file's sheet, the first time it's asked for (for this build). */
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
    })();
    return extracted;
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
      filter: {code: 'use weft css'},
      handler(code, id) {
        if (findDirectives(code)?.css !== true) return undefined;
        let stripped = blankCssDirective(stripStyles(code, parseAst));
        const sheet = scanned().files.get(id.split('?')[0]!)?.sheet;
        if (
          options.importSheets &&
          sheet !== undefined &&
          this.environment.config.consumer === 'client'
        ) {
          // On the first line, which was the directive: every other line stays where it was.
          stripped = `import ${JSON.stringify(`${sheetPrefix}${sheet}.css`)};${stripped}`;
        }
        return {code: stripped, map: null};
      },
    },

    async hotUpdate({file, type}) {
      // Once per change, in the one environment every app has.
      if (this.environment.name !== 'client' || extractor === undefined) return;
      const current = scanned();
      if (!file.endsWith(current.suffix)) return;
      const pkg = packageOf(current, file);
      if (pkg === undefined || !current.dirs.has(dirname(file))) return;
      const was = current.files.get(file);
      const now: CompiledFile | undefined =
        type === 'delete'
          ? undefined
          : readCompiledFile(pkg, file, current.suffix);
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
      if (now?.sheet === undefined) return;
      await extractAll();
      const before = extractor.sheets.get(now.sheet)?.dependencies.join();
      await extractor.extract([now]);
      if (extractor.sheets.get(now.sheet)?.dependencies.join() !== before) {
        options.onChange?.();
      }
      // The sheet's module loads again, with the new CSS, when the page does (a change to a
      // ReScript module reloads it).
      const graph = this.environment.moduleGraph;
      for (const node of graph.getModulesByFile(
        sheetPath(config.root, now.sheet),
      ) ?? []) {
        graph.invalidateModule(node);
      }
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
