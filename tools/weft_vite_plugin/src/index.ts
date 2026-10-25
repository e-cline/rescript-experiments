import {readFileSync} from 'node:fs';
import {dirname, join, relative, resolve} from 'node:path';

import {getRequestListener} from '@hono/node-server';
import {
  createRunnableDevEnvironment,
  isRunnableDevEnvironment,
  type EnvironmentModuleNode,
  type Plugin,
  type ResolvedConfig,
  type ViteDevServer,
} from 'vite';

import {cssPlugin} from './internal/cssPlugin.js';
import {findDirectives, stripDirectives} from './internal/directives.js';
import {entrypointSheets} from './internal/imports.js';
import {
  entrypoints,
  hasPpx,
  packageOf,
  readCompiledFile,
  scan,
  styleFiles,
  type Scan,
} from './internal/scan.js';
import {
  assetsCode,
  assetsId,
  bootstrapCode,
  bootstrapId,
  buildAssets,
  clientCode,
  clientId,
  clientReferencesCode,
  clientReferencesId,
  devAssets,
  ssrReferencesCode,
  refreshEvent,
  sheetsCode,
  sheetsId,
  ssrReferencesId,
  type Manifest,
} from './internal/virtualModules.js';

export type {Assets} from './internal/virtualModules.js';

export type Options = {
  /**
   * The server entry: a compiled module whose default export is a fetch handler (a function from a
   * `Request` to a promise of a `Response`, as an `@e-cline/servy` `App.t` is). Relative to the
   * root.
   */
  server: string;
  /**
   * The client entry (the bootstrap): the module the page loads first, which renders the payload
   * into the document, using `virtual:weft/client`'s `loadModule`. Relative to the root. Default:
   * `virtual:weft/bootstrap`, which runs `WeftServer.Bootstrap.main`.
   */
  client?: string;
};

/** The environment server components run in. */
export const serverEnvironment = 'rsc';
/** The browser's environment (Vite's default one). */
export const clientEnvironment = 'client';

const resolvedId = (id: string) => '\0' + id;

/** Where the client build's manifest is, in its output directory. */
const manifestFile = '.vite/manifest.json';

/** How a module id reads in an error: from the root, and a virtual module by its name. */
function displayId(root: string, id: string): string {
  if (id.startsWith('\0')) return id.slice(1);
  const path = relative(root, id.split('?')[0]!);
  return path.startsWith('..') ? id : path;
}

/**
 * Weft's server components: an `rsc` environment the server entry runs in, the client's, with every
 * entrypoint file a chunk of its own, the boundary between the two enforced, a dev server that
 * answers requests with the server entry, and a build of both. And `weft_css`'s styles, as
 * `weftCss()` has them, except that the client's modules don't import their sheets.
 */
export function weft(options: Options): Plugin[] {
  let config: ResolvedConfig;
  let scanned: Scan;
  let server: string;
  let client: string;
  /** The client build's manifest, once it's been built (`buildApp` builds the client first). */
  let manifest: Manifest | undefined;
  let devServer: ViteDevServer | undefined;

  const rescan = () => {
    scanned = scan(config.root);
  };

  /** Drops the server's assets, in development, so the next request's page has the current ones. */
  const invalidateAssets = () => {
    const graph = devServer?.environments[serverEnvironment]?.moduleGraph;
    const node = graph?.getModuleById(resolvedId(assetsId));
    if (node !== undefined) graph!.invalidateModule(node);
  };

  const css = cssPlugin({
    importSheets: false,
    scanned: () => scanned,
    rescan,
    onChange: invalidateAssets,
  });

  /** Who imports `id`, in the current environment: in a build from Rolldown, in dev from the graph. */
  function importersOf(
    context: {
      environment: {mode: string; moduleGraph?: unknown};
      getModuleInfo: (id: string) => {
        importers: readonly string[];
        dynamicImporters: readonly string[];
      } | null;
    },
    id: string,
  ): string[] {
    if (context.environment.mode === 'dev') {
      const graph = (
        context.environment as unknown as {
          moduleGraph: {
            getModuleById(id: string): EnvironmentModuleNode | undefined;
          };
        }
      ).moduleGraph;
      return [...(graph.getModuleById(id)?.importers ?? [])].flatMap((node) =>
        node.id === null ? [] : [node.id],
      );
    }
    const info = context.getModuleInfo(id);
    return info === null ? [] : [...info.importers, ...info.dynamicImporters];
  }

  /** A chain of imports from an entry (or as far back as is known) to `id`. */
  function importChain(
    context: Parameters<typeof importersOf>[0],
    id: string,
  ): string[] {
    const chain = [id];
    const seen = new Set(chain);
    for (let current = id; ;) {
      const next = importersOf(context, current).find(
        (importer) => !seen.has(importer),
      );
      if (next === undefined) return chain;
      chain.unshift(next);
      seen.add(next);
      current = next;
    }
  }

  /** Server files a client build has come across, reported once its graph is complete. */
  const serverFilesInClient = new Set<string>();

  /** The error for a client importing a server file: `chain` is the imports, ending at it. */
  function boundaryError(chain: string[]): string {
    const names = chain.map((module) => displayId(config.root, module));
    return (
      `[weft] ${names.at(-1)} is a server file ('use weft server': it has server components, or ` +
      `@@weft.server), so the client can't import it, but it does: ${names.join(' -> ')}. ` +
      'Render it from a server component instead, and pass what the client needs as props ' +
      '(or call an RPC).'
    );
  }

  const main: Plugin = {
    name: 'weft',
    // For the test harness, which needs to know the server entry.
    api: {options},

    config(userConfig) {
      const root = resolve(userConfig.root ?? process.cwd());
      const outDir = userConfig.build?.outDir ?? 'dist';
      return {
        // The server entry answers every request, pages included: no index.html.
        appType: 'custom',
        environments: {
          [clientEnvironment]: {
            build: {
              outDir: join(outDir, 'client'),
              manifest: true,
              rolldownOptions: {
                input: {
                  client:
                    options.client === undefined
                      ? bootstrapId
                      : resolve(root, options.client),
                },
              },
            },
          },
          [serverEnvironment]: {
            consumer: 'server',
            resolve: {
              // `Common.Env.isDev` is `@e-cline/js_env`'s export condition: resolved by Vite, with
              // its development/production conditions, rather than imported by Node, which would
              // always pick production.
              noExternal: ['@e-cline/js_env'],
            },
            dev: {
              // One the config already has wins: the test harness runs this environment's modules
              // in a worker.
              createEnvironment:
                userConfig.environments?.[serverEnvironment]?.dev
                  ?.createEnvironment ??
                ((name, environmentConfig) =>
                  createRunnableDevEnvironment(name, environmentConfig)),
            },
            build: {
              outDir: join(outDir, 'server'),
              rolldownOptions: {
                input: {index: resolve(root, options.server)},
                output: {entryFileNames: '[name].js'},
              },
            },
          },
        },
        builder: {
          // The client first: the server's `virtual:weft/assets` is made from its manifest.
          async buildApp(builder) {
            await builder.build(builder.environments[clientEnvironment]!);
            await builder.build(builder.environments[serverEnvironment]!);
          },
        },
      };
    },

    configResolved(resolved) {
      config = resolved;
      server = resolve(config.root, options.server);
      client =
        options.client === undefined
          ? resolvedId(bootstrapId)
          : resolve(config.root, options.client);
      if (!hasPpx(config.root)) {
        throw new Error(
          `[weft] ${join(config.root, 'rescript.json')} doesn't run ppx_weft: add ` +
            '"@e-cline/ppx_weft/ppx" to its "ppx-flags". Without it, `@weft.component` is ignored, ' +
            "and every use of a component it marks is a type error about `component<'a>`.",
        );
      }
      rescan();
    },

    buildStart() {
      // A build is run after `rescript build`, which may have changed what's an entrypoint.
      if (this.environment.mode === 'build') rescan();
      // The client build emits every stylesheet, for the server's assets to link.
      if (
        this.environment.mode === 'build' &&
        this.environment.name === clientEnvironment &&
        styleFiles(scanned).length > 0
      ) {
        // Its exports kept (nothing imports it), and with them the sheets' `?url` imports.
        this.emitFile({
          type: 'chunk',
          id: sheetsId,
          name: 'sheets',
          preserveSignature: 'strict',
        });
      }
    },

    resolveId(id) {
      if (
        id === clientReferencesId ||
        id === clientId ||
        id === bootstrapId ||
        id === assetsId ||
        id === ssrReferencesId ||
        id === sheetsId
      ) {
        // Anything but the server's environment is a client: the browser's, and a test's.
        const isClient = this.environment.name !== serverEnvironment;
        const forServer = id === assetsId || id === ssrReferencesId;
        if (isClient === forServer) {
          this.error(
            `[weft] ${id} is only for the ${isClient ? 'server' : 'client'}, but ` +
              `the ${this.environment.name} environment imports it`,
          );
        }
        return resolvedId(id);
      }
      return undefined;
    },

    async load(id) {
      if (id === resolvedId(clientReferencesId)) {
        return clientReferencesCode(entrypoints(scanned));
      } else if (id === resolvedId(ssrReferencesId)) {
        return ssrReferencesCode(entrypoints(scanned));
      } else if (id === resolvedId(clientId)) {
        return clientCode();
      } else if (id === resolvedId(bootstrapId)) {
        return bootstrapCode();
      } else if (id === resolvedId(sheetsId)) {
        return sheetsCode(styleFiles(scanned).map(({sheet}) => sheet!));
      } else if (id === resolvedId(assetsId)) {
        const files = entrypoints(scanned);
        const sheets = await css.sheets();
        const sheetsOf = entrypointSheets(scanned);
        if (this.environment.mode === 'dev') {
          return assetsCode(
            devAssets(
              config.root,
              config.base,
              client,
              files,
              sheets,
              sheetsOf,
            ),
          );
        }
        if (manifest === undefined) {
          const clientOutDir = resolve(
            config.root,
            config.environments[clientEnvironment]!.build.outDir,
          );
          try {
            manifest = JSON.parse(
              readFileSync(join(clientOutDir, manifestFile), 'utf8'),
            );
          } catch (error) {
            this.error(
              `[weft] couldn't read the client build's manifest (build the client first): ${
                (error as Error).message
              }`,
            );
          }
        }
        return assetsCode(
          buildAssets(
            manifest!,
            config.root,
            config.base,
            client,
            files,
            sheets,
            sheetsOf,
          ),
        );
      }
      return undefined;
    },

    transform: {
      // Only compiled files can have a directive, and most don't: `findDirectives` checks first.
      filter: {code: 'use weft '},
      handler(code, id) {
        const found = findDirectives(code);
        if (found === undefined) return undefined;
        if (
          found.kind === 'server' &&
          this.environment.name !== serverEnvironment
        ) {
          if (this.environment.mode === 'dev') {
            // The module graph already has whoever asked for this file.
            this.error(boundaryError(importChain(this, id)));
          }
          // In a build, who imports a file is known once the whole graph is: see `buildEnd`.
          serverFilesInClient.add(id);
        }
        return {code: stripDirectives(code, found)!, map: null};
      },
    },

    buildEnd(error) {
      if (error !== undefined || this.environment.name === serverEnvironment)
        return;
      const [first] = serverFilesInClient;
      serverFilesInClient.clear();
      if (first !== undefined)
        this.error(boundaryError(importChain(this, first)));
    },

    writeBundle(_options, bundle) {
      if (this.environment.name !== clientEnvironment) return;
      const asset = bundle[manifestFile];
      if (asset !== undefined && asset.type === 'asset') {
        manifest = JSON.parse(String(asset.source));
      }
    },

    configureServer(viteServer) {
      devServer = viteServer;
      const environment = viteServer.environments[serverEnvironment];
      // An environment that runs its modules elsewhere (the test harness's, in a worker) is
      // whoever made it's to call: no middleware.
      if (environment === undefined || !isRunnableDevEnvironment(environment)) {
        return undefined;
      }
      // After Vite's own middleware (so its modules and files are served first), every other
      // request goes to the server entry, imported afresh through the module runner each time, so
      // it's always the current code.
      return () => {
        viteServer.middlewares.use(async (request, response, next) => {
          try {
            const module = (await environment.runner.import(server)) as {
              default?: unknown;
            };
            const handler = module.default;
            if (typeof handler !== 'function') {
              throw new Error(
                `[weft] ${options.server} should export a fetch handler as its default export`,
              );
            }
            await getRequestListener(
              handler as (request: Request) => Promise<Response>,
              {
                overrideGlobalObjects: false,
                errorHandler: (error) => {
                  throw error;
                },
              },
            )(request, response);
          } catch (error) {
            next(error);
          }
        });
      };
    },

    hotUpdate({file, modules, type}) {
      if (devServer === undefined || !file.endsWith(scanned.suffix))
        return undefined;
      const clientGraph =
        devServer.environments[clientEnvironment]!.moduleGraph;

      // A file whose directive changed (or that came or went) changes the reference map.
      if (this.environment.name === clientEnvironment) {
        const pkg = packageOf(scanned, file);
        if (pkg !== undefined && scanned.dirs.has(dirname(file))) {
          const was = scanned.files.get(file);
          const now =
            type === 'delete'
              ? undefined
              : readCompiledFile(pkg, file, scanned.suffix);
          const before = was?.kind;
          const after = now?.kind;
          if (
            before !== after ||
            (was?.rpcs ?? []).join() !== (now?.rpcs ?? []).join() ||
            was?.sheet !== now?.sheet
          ) {
            // Fails (an error in the terminal) if an RPC ID is now declared twice.
            rescan();
            if ((before ?? after) === 'entrypoint') {
              for (const [environment, id] of [
                [clientEnvironment, clientReferencesId],
                [serverEnvironment, assetsId],
                [serverEnvironment, ssrReferencesId],
              ] as const) {
                const graph = devServer.environments[environment]!.moduleGraph;
                const node = graph.getModuleById(resolvedId(id));
                if (node !== undefined) graph.invalidateModule(node);
              }
              this.environment.hot.send({type: 'full-reload'});
              return [];
            }
          }
        }
      }

      if (modules.length === 0) return undefined;
      if (this.environment.name === clientEnvironment) {
        // Weft has no fast refresh: a change to client code reloads the page.
        this.environment.hot.send({type: 'full-reload'});
        return [];
      }
      if (
        this.environment.name === serverEnvironment &&
        clientGraph.getModulesByFile(file) === undefined
      ) {
        // A file only the server has: the client refetches the page's payload, keeping its state,
        // rather than reloading. (Vite's own handling, left as it is, has the runner drop the old
        // code, so the next request runs the new.)
        devServer.environments[clientEnvironment]!.hot.send({
          type: 'custom',
          event: refreshEvent,
          data: {file: displayId(config.root, file)},
        });
      }
      return undefined;
    },
  };

  // First, so its transform sees `'use weft css'` before `main`'s blanks every directive.
  return [css.plugin, main];
}

/**
 * `weft_css`'s styles, for an app without a server (`weft()` includes them): each file with styles
 * has its sheet extracted (by running the file in Node), its definitions stripped from what's
 * bundled, and its sheet imported by the module, so Vite loads it with the module's chunk.
 */
export function weftCss(): Plugin {
  return cssPlugin({importSheets: true}).plugin;
}

export default weft;
