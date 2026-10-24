// The test harness (tier 2 of the plan's tests): an app's server running in a worker thread, its
// own realm with no DOM, and a `fetch` that reaches it over a port, with the test choosing when
// each response's bytes are handed over. The client side (the bootstrap, entrypoints, the DOM) is
// the test's own: `WeftTesting.res` puts the two together for ReScript tests.

import {readFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {Worker} from 'node:worker_threads';

import {
  createServer,
  DevEnvironment,
  type HotChannel,
  type HotPayload,
  type InlineConfig,
  type ViteDevServer,
} from 'vite';

import {serverEnvironment, type Options} from './index.js';
import {entrypoints, scan} from './internal/scan.js';
import {manifestKey, type Manifest} from './internal/virtualModules.js';
import type {FromWorker, ToWorker, WorkerData} from './testingWorker.js';

export type Mode = 'source' | 'build';

export type StartOptions = {
  /** The app's root (where its `vite.config.ts` and `rescript.json` are). */
  root: string;
  /**
   * `source` (the default): the server's modules come from the app's sources, through a Vite
   * server. `build`: from the build in `buildDir`.
   */
  mode?: Mode;
  /** The build's directory, in `build` mode. Default: `dist`. */
  buildDir?: string;
  /** The Vite config file. Default: the root's `vite.config.ts`; `false` for none. */
  configFile?: string | false;
  /** More Vite config, merged in (in `source` mode). */
  config?: InlineConfig;
};

/** How a response's bytes reach the client. */
export type Delivery =
  | {type: 'immediate'}
  | {type: 'manual'}
  | {type: 'everyBytes'; size: number};

/** A response being received: its body's chunks, and where they've got to. */
type Exchange = {
  id: number;
  url: string;
  controller?: ReadableStreamDefaultController<Uint8Array>;
  /** Chunks that have arrived from the server but not been handed to the client. */
  queued: Uint8Array[];
  /** The server has sent everything (or failed: `error`). */
  ended: boolean;
  error?: string;
  /** The client has everything, or stopped reading. */
  closed: boolean;
};

const workerFile = new URL(
  import.meta.url.endsWith('.ts') ? './testingWorker.ts' : './testingWorker.js',
  import.meta.url,
);

/** The id of an entrypoint file, and the URL of its built chunk. */
export type BuiltEntrypoint = {id: string; file: string};

export class App {
  readonly root: string;
  readonly mode: Mode;
  /** The build's directory (`build` mode). */
  readonly buildDir: string;
  /** The Vite server whose `rsc` environment the worker's modules come from (`source` mode). */
  readonly vite: ViteDevServer | undefined;
  private readonly worker: Worker;
  private nextId = 0;
  private readonly exchanges = new Map<number, Exchange>();
  private readonly pendingCalls = new Map<
    number,
    {resolve: (value: unknown) => void; reject: (error: Error) => void}
  >();
  private readonly responses = new Map<
    number,
    {resolve: (response: Response) => void; reject: (error: Error) => void}
  >();
  /** Arrival order of chunks not yet delivered, for `deliver`. */
  private readonly arrivals: number[] = [];
  private listeners = new Set<() => void>();
  delivery: Delivery = {type: 'immediate'};
  /** Every request made, by URL, in order. */
  readonly requests: string[] = [];
  /**
   * The cookies the server has set, by name, as a browser keeps them for the app's origin: sent
   * with every request after, until they expire or `clearCookies`.
   */
  private readonly jar = new Map<string, string>();
  /** How `rewriteBodies` changes the bodies of requests to paths containing `matching`. */
  private rewrite:
    | {matching: string; change: (body: string) => string}
    | undefined;

  constructor(
    root: string,
    mode: Mode,
    vite: ViteDevServer | undefined,
    worker: Worker,
    buildDir = resolve(root, 'dist'),
  ) {
    this.root = root;
    this.mode = mode;
    this.buildDir = buildDir;
    this.vite = vite;
    this.worker = worker;
    worker.on('message', (message: FromWorker) => this.receive(message));
  }

  private post(message: ToWorker, transfer: ArrayBuffer[] = []) {
    this.worker.postMessage(message, transfer);
  }

  private changed() {
    for (const listener of [...this.listeners]) listener();
  }

  /**
   * Changes the body of each request whose path contains `matching`, before the server gets it,
   * until `stopRewriting` (a client older or newer than the server, say, or a forged request).
   */
  rewriteBodies(matching: string, change: (body: string) => string) {
    this.rewrite = {matching, change};
  }

  stopRewriting() {
    this.rewrite = undefined;
  }

  /** The cookies the client has, by name (what the server's `Set-Cookie` headers left). */
  cookies(): Record<string, string> {
    return Object.fromEntries(this.jar);
  }

  /** Forgets every cookie, as a new visitor (or a cleared browser) would. */
  clearCookies() {
    this.jar.clear();
  }

  /** Keeps (or, for one that has expired, forgets) the cookie a `Set-Cookie` header sets. */
  private keepCookie(header: string) {
    const [pair = '', ...attributes] = header.split(';');
    const equals = pair.indexOf('=');
    if (equals <= 0) return;
    const name = pair.slice(0, equals).trim();
    const value = pair.slice(equals + 1).trim();
    const expired = attributes.some((attribute) => {
      const [key = '', setting = ''] = attribute
        .split('=')
        .map((part) => part.trim());
      return (
        (key.toLowerCase() === 'max-age' && Number(setting) <= 0) ||
        (key.toLowerCase() === 'expires' && Date.parse(setting) <= Date.now())
      );
    });
    if (expired) {
      this.jar.delete(name);
    } else {
      this.jar.set(name, value);
    }
  }

  /** Calls `listener` whenever a chunk arrives, is delivered, or a response ends. */
  onChange(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private receive(message: FromWorker) {
    switch (message.type) {
      case 'invoke':
        void this.invoke(message.id, message.data);
        break;
      case 'response': {
        const exchange = this.exchanges.get(message.id);
        const waiting = this.responses.get(message.id);
        this.responses.delete(message.id);
        for (const [name, value] of message.headers) {
          if (name.toLowerCase() === 'set-cookie') this.keepCookie(value);
        }
        if (exchange === undefined || waiting === undefined) break;
        const body = new ReadableStream<Uint8Array>({
          start: (controller) => {
            exchange.controller = controller;
          },
          pull: () => {},
          cancel: () => {
            exchange.closed = true;
            exchange.queued = [];
            this.post({type: 'cancel', id: exchange.id});
            this.changed();
          },
        });
        // Some statuses can't have a body at all.
        const noBody = [101, 204, 205, 304].includes(message.status);
        if (noBody) exchange.closed = true;
        waiting.resolve(
          new Response(noBody ? null : body, {
            status: message.status,
            headers: message.headers,
          }),
        );
        break;
      }
      case 'chunk': {
        const exchange = this.exchanges.get(message.id);
        if (exchange === undefined || exchange.closed) break;
        exchange.queued.push(new Uint8Array(message.bytes));
        this.arrivals.push(exchange.id);
        this.flush();
        break;
      }
      case 'end': {
        const exchange = this.exchanges.get(message.id);
        if (exchange === undefined) break;
        exchange.ended = true;
        this.flush();
        break;
      }
      case 'error': {
        const exchange = this.exchanges.get(message.id);
        const waiting = this.responses.get(message.id);
        this.responses.delete(message.id);
        waiting?.reject(new Error(message.message));
        if (exchange !== undefined) {
          exchange.ended = true;
          exchange.error = message.message;
          this.flush();
        }
        break;
      }
      case 'called': {
        const call = this.pendingCalls.get(message.id);
        this.pendingCalls.delete(message.id);
        if (message.error !== undefined) {
          call?.reject(new Error(message.error));
        } else {
          call?.resolve(message.value);
        }
        break;
      }
    }
  }

  private async invoke(id: number, data: unknown) {
    const environment = this.vite!.environments[serverEnvironment]!;
    const result = await environment.hot.handleInvoke(data as HotPayload);
    this.post({type: 'invoked', id, result});
  }

  /** Hands an exchange's queued bytes to the client, as the delivery mode allows. */
  private flush() {
    if (this.delivery.type !== 'manual') {
      for (const exchange of this.exchanges.values()) this.drain(exchange);
    }
    for (const exchange of this.exchanges.values()) this.closeIfDone(exchange);
    this.changed();
  }

  private hand(exchange: Exchange, bytes: Uint8Array) {
    if (exchange.closed || exchange.controller === undefined) return;
    if (this.delivery.type === 'everyBytes') {
      for (let at = 0; at < bytes.length; at += this.delivery.size) {
        exchange.controller.enqueue(bytes.slice(at, at + this.delivery.size));
      }
    } else {
      exchange.controller.enqueue(bytes);
    }
  }

  private drain(exchange: Exchange) {
    if (exchange.controller === undefined) return;
    for (const bytes of exchange.queued.splice(0)) this.hand(exchange, bytes);
    for (let i = this.arrivals.length - 1; i >= 0; i--) {
      if (this.arrivals[i] === exchange.id) this.arrivals.splice(i, 1);
    }
  }

  private closeIfDone(exchange: Exchange) {
    if (
      exchange.closed ||
      !exchange.ended ||
      exchange.queued.length > 0 ||
      exchange.controller === undefined
    ) {
      return;
    }
    exchange.closed = true;
    if (exchange.error !== undefined) {
      exchange.controller.error(new Error(exchange.error));
    } else {
      exchange.controller.close();
    }
    this.exchanges.delete(exchange.id);
  }

  /**
   * A `fetch` to the server, through the worker: the request's method, URL, headers and body go
   * over, and the response's body comes back as the delivery mode allows.
   */
  readonly fetch = async (
    input: string | URL | Request,
    init?: RequestInit,
  ): Promise<Response> => {
    const request = new Request(
      new URL(
        String(input instanceof Request ? input.url : input),
        'http://localhost',
      ),
      input instanceof Request ? input : init,
    );
    let body =
      request.body === null
        ? null
        : new Uint8Array(await request.arrayBuffer());
    const rewrite = this.rewrite;
    if (
      body !== null &&
      rewrite !== undefined &&
      new URL(request.url).pathname.includes(rewrite.matching)
    ) {
      body = new TextEncoder().encode(
        rewrite.change(new TextDecoder().decode(body)),
      );
    }
    const id = this.nextId++;
    this.requests.push(
      new URL(request.url).pathname + new URL(request.url).search,
    );
    this.exchanges.set(id, {
      id,
      url: request.url,
      queued: [],
      ended: false,
      closed: false,
    });
    const response = new Promise<Response>((resolve, reject) => {
      this.responses.set(id, {resolve, reject});
    });
    request.signal.addEventListener('abort', () => {
      const exchange = this.exchanges.get(id);
      if (exchange !== undefined && !exchange.closed) {
        exchange.closed = true;
        exchange.queued = [];
        this.post({type: 'cancel', id});
        try {
          exchange.controller?.error(new DOMException('aborted', 'AbortError'));
        } catch {}
        this.changed();
      }
      this.responses.get(id)?.reject(new DOMException('aborted', 'AbortError'));
      this.responses.delete(id);
    });
    const headers = [...request.headers];
    // The browser's cookies for the app, unless the request brought its own.
    if (this.jar.size > 0 && !request.headers.has('cookie')) {
      headers.push([
        'cookie',
        [...this.jar].map(([name, value]) => `${name}=${value}`).join('; '),
      ]);
    }
    this.post({
      type: 'request',
      id,
      method: request.method,
      url: request.url,
      headers,
      body,
    });
    return response;
  };

  /** Hands over the oldest chunk not yet delivered (in `manual` delivery). Whether there was one. */
  deliver(): boolean {
    const id = this.arrivals.shift();
    if (id === undefined) return false;
    const exchange = this.exchanges.get(id);
    const bytes = exchange?.queued.shift();
    if (exchange !== undefined && bytes !== undefined)
      this.hand(exchange, bytes);
    if (exchange !== undefined) this.closeIfDone(exchange);
    this.changed();
    return true;
  }

  /** Hands over every chunk that has arrived. */
  deliverAll() {
    while (this.deliver()) {}
    for (const exchange of [...this.exchanges.values()])
      this.closeIfDone(exchange);
  }

  /** How many chunks have arrived and not been delivered. */
  get waiting(): number {
    return this.arrivals.length;
  }

  /** How many requests have no response yet. */
  get awaitingResponses(): number {
    return this.responses.size;
  }

  /** How many responses are still open: not yet finished by the server, or not yet all delivered. */
  get open(): number {
    return [...this.exchanges.values()].filter((exchange) => !exchange.closed)
      .length;
  }

  /**
   * Calls `name` in the server's module `module` (a path from the root), with `args`, in the
   * worker: the same module instance the app's server uses. Its result must be cloneable.
   */
  callServer(
    module: string,
    name: string,
    args: unknown[] = [],
  ): Promise<unknown> {
    const id = this.nextId++;
    const done = new Promise<unknown>((resolve, reject) => {
      this.pendingCalls.set(id, {resolve, reject});
    });
    this.post({
      type: 'call',
      id,
      module: resolve(this.root, module),
      name,
      args,
    });
    return done;
  }

  /** Which of `names` are globals in the server's realm. */
  serverGlobals(names: string[]): Promise<string[]> {
    const id = this.nextId++;
    const done = new Promise<unknown>((resolve, reject) => {
      this.pendingCalls.set(id, {resolve, reject});
    });
    this.post({type: 'globals', id, names});
    return done as Promise<string[]>;
  }

  async close() {
    await this.worker.terminate();
    await this.vite?.close();
  }
}

/** The weft plugin's options, from the Vite server's config. */
function pluginOptions(vite: ViteDevServer): Options {
  const plugin = vite.config.plugins.find((found) => found.name === 'weft');
  const options = (plugin?.api as {options?: Options} | undefined)?.options;
  if (options === undefined) {
    throw new Error("[weft] the app's Vite config doesn't use the weft plugin");
  }
  return options;
}

/** Starts the app's server in a worker. */
export async function start(options: StartOptions): Promise<App> {
  const root = resolve(options.root);
  const mode = options.mode ?? 'source';
  if (mode === 'build') {
    const buildDir = resolve(root, options.buildDir ?? 'dist');
    const worker = new Worker(workerFile, {
      workerData: {
        mode,
        root,
        serverBuild: join(buildDir, 'server/index.js'),
      } satisfies WorkerData,
    });
    await ready(worker);
    return new App(root, mode, undefined, worker, buildDir);
  }

  let worker: Worker | undefined;
  const channel: HotChannel = {
    // The worker is this process's: nothing reaches it over a network.
    skipFsCheck: true,
    send: (payload) =>
      worker?.postMessage({type: 'hot', payload} satisfies ToWorker),
    on: () => {},
    off: () => {},
    listen: () => {},
    close: () => {},
  };
  const configFile =
    options.configFile === undefined
      ? join(root, 'vite.config.ts')
      : options.configFile;
  const vite = await createServer({
    ...options.config,
    root,
    configFile,
    logLevel: options.config?.logLevel ?? 'silent',
    server: {middlewareMode: true, ws: false, ...options.config?.server},
    environments: {
      ...options.config?.environments,
      [serverEnvironment]: {
        ...options.config?.environments?.[serverEnvironment],
        dev: {
          createEnvironment: (name, config) =>
            new DevEnvironment(name, config, {hot: true, transport: channel}),
        },
      },
    },
  });
  const server = resolve(root, pluginOptions(vite).server);
  worker = new Worker(workerFile, {
    workerData: {mode, root, server} satisfies WorkerData,
  });
  await ready(worker);
  return new App(root, mode, vite, worker);
}

function ready(worker: Worker): Promise<void> {
  return new Promise((resolve, reject) => {
    const listener = (message: FromWorker) => {
      if (message.type === 'ready') {
        worker.off('message', listener);
        resolve();
      } else if (message.type === 'failed') {
        worker.off('message', listener);
        reject(new Error(message.message));
      }
    };
    worker.on('message', listener);
    worker.once('error', reject);
  });
}

/**
 * The entrypoint files of a build, by id, each with its chunk's path (absolute): how a client
 * loads them in `build` mode.
 */
export function builtEntrypoints(
  root: string,
  buildDir = 'dist',
): BuiltEntrypoint[] {
  const clientDir = resolve(root, buildDir, 'client');
  const manifest = JSON.parse(
    readFileSync(join(clientDir, '.vite/manifest.json'), 'utf8'),
  ) as Manifest;
  return entrypoints(scan(root)).flatMap(({id, file}) => {
    const chunk = manifest[manifestKey(root, file)];
    return chunk === undefined ? [] : [{id, file: join(clientDir, chunk.file)}];
  });
}

/** A piece of a page's body, as its parser would come to it: one top-level node at a time. */
export type Piece =
  /** `#root`, with the shell's HTML in it (if the server rendered one). */
  | {type: 'root'; attributes: [string, string][]; html: string}
  /** An inline script: a row, the swap runtime, or a swap. */
  | {type: 'script'; code: string}
  /** Anything else: a preload, a boundary's segment, the end of the body. */
  | {type: 'markup'; html: string};

const voidElements = new Set([
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'source',
  'track',
  'wbr',
]);
const rawTextElements = new Set(['script', 'style', 'textarea', 'title']);

/** A comment, a closing tag, an opening tag (its name and attributes), or a run of text. */
const token =
  /<!--[\s\S]*?-->|<\/([a-zA-Z][^\s/>]*)\s*>|<([a-zA-Z][^\s/>]*)((?:[^>"']|"[^"]*"|'[^']*')*)>|[^<]+/y;

/** How long the node at the start of `text` is, or `undefined` if it hasn't all arrived. */
function nodeLength(text: string): number | undefined {
  let depth = 0;
  let at = 0;
  for (;;) {
    token.lastIndex = at;
    const match = token.exec(text);
    if (match === null) return undefined;
    at = token.lastIndex;
    const [whole, close, open, attributes] = match;
    if (open !== undefined) {
      const name = open.toLowerCase();
      if (rawTextElements.has(name)) {
        // Its text runs to its closing tag, whatever it looks like.
        const end = text.toLowerCase().indexOf(`</${name}`, at);
        const closed = end === -1 ? -1 : text.indexOf('>', end);
        if (closed === -1) return undefined;
        at = closed + 1;
        if (depth === 0) return at;
      } else if (!voidElements.has(name) && !attributes!.endsWith('/')) {
        depth++;
      } else if (depth === 0) {
        return at;
      }
    } else if (close !== undefined) {
      depth--;
      if (depth <= 0) return at;
    } else if (depth === 0) {
      // A comment is whole; a run of text only once something follows it.
      return whole.startsWith('<!--') || at < text.length ? at : undefined;
    }
  }
}

const attribute = /([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;

const decodeEntities = (text: string) =>
  text
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

function toPiece(node: string): Piece {
  const open = /^<([a-zA-Z][^\s/>]*)((?:[^>"']|"[^"]*"|'[^']*')*)>/.exec(node);
  const name = open?.[1]!.toLowerCase();
  if (name === 'script' && open![2]!.trim() === '') {
    return {
      type: 'script',
      code: node.slice(open![0].length, node.lastIndexOf('</')),
    };
  }
  if (name === 'div') {
    const attributes = [...open![2]!.matchAll(attribute)].map(
      ([, key, ...values]): [string, string] => [
        key!.toLowerCase(),
        decodeEntities(values.find((value) => value !== undefined) ?? ''),
      ],
    );
    if (attributes.some(([key, value]) => key === 'id' && value === 'root')) {
      return {
        type: 'root',
        attributes,
        html: node.slice(open![0].length, node.lastIndexOf('</')),
      };
    }
  }
  return {type: 'markup', html: node};
}

const rowScript =
  /<script>\(self\.__weft\|\|=\[\]\)\.push\((?:"(?:[^"\\]|\\.)*"|null)\)<\/script>/g;

/**
 * Reads a page's HTML as it arrives, as a streaming parser would: `onPiece` gets the head's inline
 * scripts, then each top-level node of the body once it has all arrived (`#root` with the shell in
 * it, each inline script, each segment), in order. Resolves with the whole HTML, with the rows' scripts taken out, once it has
 * all arrived.
 */
export async function readPage(
  html: ReadableStream<Uint8Array>,
  onPiece: (piece: Piece) => void,
): Promise<string> {
  const decoder = new TextDecoder();
  const reader = html.getReader();
  let whole = '';
  let text = '';
  let inBody = false;
  const take = () => {
    while (!inBody) {
      // The head: its inline scripts run (the event runtime), the rest is the test's own document's.
      const body = /<body(?:[^>"']|"[^"]*"|'[^']*')*>/.exec(text);
      const script = text.indexOf('<script>');
      if (script !== -1 && (body === null || script < body.index)) {
        const end = text.indexOf('</script>', script);
        if (end === -1) return;
        onPiece({type: 'script', code: text.slice(script + 8, end)});
        text = text.slice(end + 9);
        continue;
      }
      if (body === null) return;
      text = text.slice(body.index + body[0].length);
      inBody = true;
    }
    for (;;) {
      const length = text === '' ? undefined : nodeLength(text);
      if (length === undefined) return;
      const node = text.slice(0, length);
      text = text.slice(length);
      onPiece(toPiece(node));
    }
  };
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    const chunk = decoder.decode(value, {stream: true});
    whole += chunk;
    text += chunk;
    take();
  }
  const last = decoder.decode();
  whole += last;
  text += last;
  take();
  if (inBody && text !== '') onPiece({type: 'markup', html: text});
  return whole.replace(rowScript, '');
}

// The client side: a page in the test's DOM.

/** What the harness needs from the client's code, which only the test's module graph can import. */
export type ClientSide = {
  /** The reference map's `loadModule` (`virtual:weft/client-references`), in `source` mode. */
  loadModule: (id: string) => Promise<unknown>;
  /** `WeftServer.Bootstrap.start`, resolving with the page's `Navigation.t`. */
  start: (options: {
    loadModule: (id: string) => Promise<unknown>;
    fetch: (
      url: string,
      signal: AbortSignal,
    ) => Promise<ReadableStream<Uint8Array>>;
    container: Element;
    url: string;
    /** Aborted when the page closes: the bootstrap stops it (unmounts its root). */
    signal: AbortSignal;
  }) => Promise<unknown>;
  /** `WeftDom.Client.act`: runs `f`, then renders and runs effects. */
  act: (f: () => void) => void;
};

export type OpenOptions = {
  url: string;
  container: Element;
  delivery?: Delivery;
  client: ClientSide;
  /**
   * Whether the bootstrap runs, once `#root` has arrived (the default), or only when the test calls
   * `startBootstrap`: as if its chunk loaded late, or never. The page's own inline scripts run
   * either way.
   */
  bootstrap?: boolean;
};

/** Where `console.error` and `console.warn` are collected: the page opened last's `warnings`. */
let collecting: string[] | undefined;
let consoleWrapped = false;

function collectConsole() {
  if (consoleWrapped) return;
  consoleWrapped = true;
  for (const level of ['error', 'warn'] as const) {
    const original = console[level];
    console[level] = (...args: unknown[]) => {
      collecting?.push(args.map(String).join(' '));
      original.apply(console, args);
    };
  }
}

/** A plain object (a module, or a module inside one, as ReScript compiles it). */
const isPlain = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' &&
  value !== null &&
  [Object.prototype, null].includes(Object.getPrototypeOf(value));

/** A node, as a test reads it in a list of what changed. */
function describeNode(node: Node): string {
  if (node.nodeType === 3) return JSON.stringify(node.textContent);
  if (node.nodeType === 8) return `<!--${node.textContent}-->`;
  const element = node as Element;
  return element.id === ''
    ? element.tagName.toLowerCase()
    : `${element.tagName.toLowerCase()}#${element.id}`;
}

export class Page {
  readonly app: App;
  readonly container: Element;
  /**
   * The page's `Navigation.t` (`source` mode), once the bootstrap has started on its first payload
   * (in `build` mode, once the bootstrap's chunk has run).
   */
  readonly started: Promise<unknown>;
  /** What `console.error` and `console.warn` said since the page opened: hydration's warnings. */
  readonly warnings: string[] = [];
  /**
   * The nodes the HTML has made under the container: the shell's, and each segment's as it's
   * swapped in, less those the swaps took out (the fallbacks). Hydration should keep them all.
   */
  htmlNodes: Node[] = [];
  /** The HTML with the rows taken out, once it has all arrived. */
  readonly shell: Promise<string>;
  /** Each entrypoint's renders, by id (`source` mode). */
  readonly renders = new Map<string, number>();
  /** The entrypoint files loaded, in order (`source` mode). */
  readonly loads: string[] = [];
  private readonly act: (f: () => void) => void;
  /** Where the app's requests had got to when the page opened. */
  private readonly firstRequest: number;
  private held: (() => void)[] | undefined;
  /** Which loads `holdLoads` holds: those whose id contains this. */
  private holding = '';
  private loading = 0;
  /** How many of the loads under way are held by `holdLoads`. */
  private heldLoads = 0;
  private readonly wrapped = new Map<unknown, unknown>();
  private readonly start: (page: Page) => Promise<unknown>;
  private rootArrived = false;
  private wantsBootstrap: boolean;
  private bootstrapped = false;
  private resolveStarted!: (started: Promise<unknown>) => void;
  /** Aborted by `close`. */
  readonly closing = new AbortController();

  constructor(
    app: App,
    container: Element,
    act: (f: () => void) => void,
    start: (page: Page) => Promise<unknown>,
    html: Promise<Response>,
    firstRequest: number,
    bootstrap: boolean,
  ) {
    this.app = app;
    this.container = container;
    this.act = act;
    this.firstRequest = firstRequest;
    this.start = start;
    this.wantsBootstrap = bootstrap;
    this.started = new Promise((resolve) => {
      this.resolveStarted = resolve;
    });
    // A page that fails to start fails the test through `started`, not as an unhandled rejection.
    this.started.catch(() => {});
    this.shell = html.then((response) =>
      readPage(response.body!, (piece) => this.apply(piece)),
    );
    this.shell.catch(() => {});
  }

  /** A piece of the page's body, put in the document as the parser would. */
  private apply(piece: Piece) {
    const document = this.container.ownerDocument;
    switch (piece.type) {
      case 'root':
        // The test's container stands for `#root`, without taking its id.
        for (const [name, value] of piece.attributes) {
          if (name !== 'id') this.container.setAttribute(name, value);
        }
        this.container.innerHTML = piece.html;
        this.htmlNodes = this.snapshot();
        this.rootArrived = true;
        this.bootstrapIfWanted();
        break;
      case 'script': {
        // As an inline script runs: in the global scope. What it changes under the container (a
        // swap: nothing renders while it runs) is the HTML's doing.
        const before = this.rootArrived ? this.snapshot() : [];
        (0, eval)(piece.code);
        if (this.rootArrived) {
          const after = this.snapshot();
          const kept = new Set(after);
          const was = new Set(before);
          this.htmlNodes = [
            ...this.htmlNodes.filter((node) => kept.has(node)),
            ...after.filter((node) => !was.has(node)),
          ];
        }
        break;
      }
      case 'markup': {
        const holder = document.createElement('template');
        holder.innerHTML = piece.html;
        document.body.append(holder.content);
        break;
      }
    }
  }

  private bootstrapIfWanted() {
    if (!this.wantsBootstrap || !this.rootArrived || this.bootstrapped) return;
    this.bootstrapped = true;
    this.resolveStarted(this.start(this));
  }

  /**
   * Closes the page, as leaving it would: its root is unmounted (its effects cleaned up, so its
   * intervals and subscriptions stop) and it stops following the history. Opening another page
   * closes the one before.
   */
  close() {
    if (this.closing.signal.aborted) return;
    this.act(() => this.closing.abort());
    if (openedLast === this) openedLast = undefined;
  }

  /** Runs the bootstrap (on a page opened without it), now or once `#root` arrives. */
  startBootstrap() {
    this.wantsBootstrap = true;
    this.bootstrapIfWanted();
  }

  /**
   * Waits until the bootstrap has hydrated the page (or rendered it, with no HTML to hydrate): it
   * has started, every entrypoint it's loading has loaded (but those `holdLoads` holds), and the
   * renders that follow are done. A boundary still streaming hydrates later, once its content
   * arrives, as does one waiting on a held load.
   */
  async hydrated(timeout = 5000): Promise<void> {
    const deadline = Date.now() + timeout;
    await this.started;
    for (let quiet = 0; quiet < 3;) {
      this.act(() => {});
      await new Promise((done) => setTimeout(done, 5));
      // In `build` mode the loads are the build's own: its first element having its props says
      // hydration got there.
      const loaded =
        this.app.mode === 'source'
          ? this.loading === this.heldLoads
          : this.container.firstElementChild === null ||
            '$$resFiberProps' in this.container.firstElementChild;
      quiet = loaded ? quiet + 1 : 0;
      if (Date.now() > deadline) {
        throw new Error(
          `[weft] timed out waiting for hydration; the page shows: ${this.container.innerHTML}`,
        );
      }
    }
  }

  /**
   * `module` (the file `path`, or a module in one) with each entrypoint's `make` wrapped to count
   * its renders: the same wrapped module every time, so components keep their identity.
   */
  wrapModule(module: unknown, path: string): unknown {
    const found = this.wrapped.get(module);
    if (found !== undefined) return found;
    if (!isPlain(module)) return module;
    const copy: Record<string, unknown> = {};
    this.wrapped.set(module, copy);
    for (const [name, value] of Object.entries(module)) {
      if (name === 'make' && typeof value === 'function') {
        const make = value as (props: unknown) => unknown;
        copy[name] = (props: unknown) => {
          this.renders.set(path, (this.renders.get(path) ?? 0) + 1);
          return make(props);
        };
      } else {
        // ReScript exports a module named like a JavaScript global (`Error`) as `$$Error`.
        const moduleName = name.startsWith('$$') ? name.slice(2) : name;
        const inner = path.endsWith('#')
          ? `${path}${moduleName}`
          : `${path}.${moduleName}`;
        copy[name] = this.wrapModule(value, inner);
      }
    }
    return copy;
  }

  /** `loadModule`, recording each load, held while `holdLoads` is on, and wrapping entrypoints. */
  loader(loadModule: (id: string) => Promise<unknown>) {
    return async (id: string) => {
      this.loads.push(id);
      this.loading++;
      try {
        if (this.held !== undefined && id.includes(this.holding)) {
          const held = this.held;
          this.heldLoads++;
          await new Promise<void>((resolve) => held.push(resolve));
          this.heldLoads--;
        }
        // Entrypoint ids are `<file>#<module path>`, and renders are counted by them.
        return this.wrapModule(await loadModule(id), `${id}#`);
      } finally {
        this.loading--;
      }
    };
  }

  /** Holds entrypoint loads (they wait) until `releaseLoads`: those whose id contains `matching`. */
  holdLoads(matching = '') {
    this.held ??= [];
    this.holding = matching;
  }

  releaseLoads() {
    const held = this.held ?? [];
    this.held = undefined;
    for (const release of held) release();
  }

  /** The requests made since the page opened (its own first among them), by path and query. */
  get requests(): string[] {
    return this.app.requests.slice(this.firstRequest);
  }

  /** How many times the entrypoint `id` (`<file>#<module path>`) has rendered. */
  renderCount(id: string): number {
    return this.renders.get(id) ?? 0;
  }

  /** Every node under the container now, to compare with later (`removedSince`). */
  snapshot(): Node[] {
    const nodes: Node[] = [];
    const walker = this.container.ownerDocument.createTreeWalker(
      this.container,
    );
    for (
      let node = walker.nextNode();
      node !== null;
      node = walker.nextNode()
    ) {
      nodes.push(node);
    }
    return nodes;
  }

  /** The nodes in `snapshot` no longer under the container: what an update replaced. */
  removedSince(snapshot: Node[]): string[] {
    return snapshot
      .filter((node) => !this.container.contains(node))
      .map(describeNode);
  }

  /** Hands the client the next chunk the server sent. */
  deliver(): boolean {
    let delivered = false;
    this.act(() => {
      delivered = this.app.deliver();
    });
    return delivered;
  }

  /** Whether anything is under way on the client: a load, or a request with no response yet. */
  private get busy(): boolean {
    return this.loading > 0 || this.app.awaitingResponses > 0;
  }

  /**
   * Delivers everything, and waits until things are quiet: nothing to deliver, no load or request
   * under way, and the DOM unchanged, for a while. (A page streams for as long as the server has
   * something to send, so "every response has ended" can't be the test: use `waitFor` for what's
   * expected to happen.)
   */
  async settle(): Promise<void> {
    let quiet = 0;
    let last = this.container.innerHTML;
    for (let turn = 0; turn < 1000 && quiet < 8; turn++) {
      this.act(() => this.app.deliverAll());
      await new Promise((done) => setTimeout(done, 5));
      this.act(() => {});
      const now = this.container.innerHTML;
      quiet =
        !this.busy && this.app.waiting === 0 && now === last ? quiet + 1 : 0;
      last = now;
    }
  }

  /**
   * Delivers what arrives (unless delivery is `manual`), and waits until `predicate` holds. Fails
   * after `timeout` milliseconds, saying what the page showed.
   */
  async waitFor(predicate: () => boolean, timeout = 5000): Promise<void> {
    const deadline = Date.now() + timeout;
    for (;;) {
      if (this.app.delivery.type !== 'manual')
        this.act(() => this.app.deliverAll());
      this.act(() => {});
      if (predicate()) return;
      if (Date.now() > deadline) {
        throw new Error(
          `[weft] timed out waiting; the page shows: ${this.container.innerHTML}`,
        );
      }
      await new Promise((done) => setTimeout(done, 5));
    }
  }

  /** Waits a few turns of the event loop without delivering anything. */
  async idle(): Promise<void> {
    for (let turn = 0; turn < 5; turn++) {
      await new Promise((done) => setTimeout(done, 0));
      this.act(() => {});
    }
  }
}

let builtBootstrapImported = false;

/** The page opened last, which opening another closes. */
let openedLast: Page | undefined;

/**
 * Opens `url` in `container`: requests its HTML through the server and applies it as the browser's
 * parser would, as it arrives (the shell into the container, then each inline script and segment, in
 * order: the rows pushed, boundaries swapped in), and once the shell's in, starts the client, which
 * hydrates it. In `build` mode, the client is the build's own bootstrap, which can only be imported
 * once per test file (its modules are shared), so a build-mode test file opens one page, and moves
 * on by following links. Segments go in the document's body, and the page's runtime finds them by
 * id, so one page is open in a document at a time.
 */
export function openPage(app: App, options: OpenOptions): Page {
  openedLast?.close();
  app.delivery = options.delivery ?? {type: 'immediate'};
  const self = globalThis as {__weft?: unknown};
  delete self.__weft;
  const container = options.container;
  container.removeAttribute('data-weft-html');
  container.innerHTML = '';
  collectConsole();
  const firstRequest = app.requests.length;
  // Entrypoints' own requests (a form posting, say) go to the server too.
  (globalThis as {fetch: typeof fetch}).fetch = app.fetch as typeof fetch;
  const html = app.fetch(options.url, {headers: {Accept: 'text/html'}});
  const payloadFetch = async (url: string, signal: AbortSignal) => {
    const response = await app.fetch(url, {
      headers: {Accept: 'text/x-weft-payload'},
      signal,
    });
    if (!response.ok) {
      throw new Error(
        `[weft] fetching ${url} failed with status ${response.status}`,
      );
    }
    return response.body!;
  };
  const opened = (start: (page: Page) => Promise<unknown>) => {
    const page = new Page(
      app,
      container,
      options.client.act,
      start,
      html,
      firstRequest,
      options.bootstrap ?? true,
    );
    collecting = page.warnings;
    openedLast = page;
    return page;
  };
  if (app.mode === 'source') {
    return opened((page) =>
      options.client.start({
        loadModule: page.loader(options.client.loadModule),
        fetch: payloadFetch,
        container,
        url: options.url,
        signal: page.closing.signal,
      }),
    );
  }
  if (builtBootstrapImported) {
    throw new Error(
      '[weft] a build-mode test file can open one page (follow links from it)',
    );
  }
  builtBootstrapImported = true;
  const document = container.ownerDocument;
  if (container.id !== 'root' || !document.body.contains(container)) {
    throw new Error(
      "[weft] in build mode, the container is the document's #root",
    );
  }
  const window = document.defaultView as unknown as {
    history: History;
    fetch: typeof fetch;
  };
  window.history.replaceState(null, '', options.url);
  return opened(async () => {
    const bootstrap = builtBootstrap(app.buildDir);
    await import(/* @vite-ignore */ bootstrap);
    return undefined;
  });
}

/** The built bootstrap's chunk: the client build's one entry. */
function builtBootstrap(buildDir: string): string {
  const clientDir = join(buildDir, 'client');
  const manifest = JSON.parse(
    readFileSync(join(clientDir, '.vite/manifest.json'), 'utf8'),
  ) as Manifest;
  const entry = Object.values(manifest).find((chunk) => chunk.isEntry);
  if (entry === undefined)
    throw new Error('[weft] the client build has no entry');
  return join(clientDir, entry.file);
}
