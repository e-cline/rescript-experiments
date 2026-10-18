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
    this.post({
      type: 'request',
      id,
      method: request.method,
      url: request.url,
      headers: [...request.headers],
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

/**
 * The rows a page's HTML carries (`WeftServer.Page`'s inline scripts), read from `html` as it
 * arrives: `onRow` gets each row's text, then `null` once the payload is complete. Resolves with
 * the HTML with the scripts taken out (the shell), once it has all arrived.
 */
export async function readPage(
  html: ReadableStream<Uint8Array>,
  onRow: (row: string | null) => void,
): Promise<string> {
  const decoder = new TextDecoder();
  const reader = html.getReader();
  let text = '';
  let shell = '';
  const script =
    /<script>\(self\.__weft\|\|=\[\]\)\.push\(("(?:[^"\\]|\\.)*"|null)\)<\/script>/y;
  const take = () => {
    for (;;) {
      const start = text.indexOf('<script>(self.__weft');
      if (start === -1) {
        // Keep what might be the start of a script for the next chunk.
        const keep = text.lastIndexOf('<');
        const cut = keep === -1 ? text.length : keep;
        shell += text.slice(0, cut);
        text = text.slice(cut);
        return;
      }
      shell += text.slice(0, start);
      text = text.slice(start);
      script.lastIndex = 0;
      const match = script.exec(text);
      if (match === null) return;
      onRow(JSON.parse(match[1]!) as string | null);
      text = text.slice(match[0].length);
    }
  };
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    text += decoder.decode(value, {stream: true});
    take();
  }
  text += decoder.decode();
  take();
  return shell + text;
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
  }) => Promise<unknown>;
  /** `WeftDom.Client.act`: runs `f`, then renders and runs effects. */
  act: (f: () => void) => void;
};

export type OpenOptions = {
  url: string;
  container: Element;
  delivery?: Delivery;
  client: ClientSide;
};

/** A plain object (a module, or a module inside one, as ReScript compiles it). */
const isPlain = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' &&
  value !== null &&
  [Object.prototype, null].includes(Object.getPrototypeOf(value));

/** A node, as a test reads it in a list of what changed. */
function describeNode(node: Node): string {
  if (node.nodeType === 3) return JSON.stringify(node.textContent);
  const element = node as Element;
  return element.id === ''
    ? element.tagName.toLowerCase()
    : `${element.tagName.toLowerCase()}#${element.id}`;
}

export class Page {
  readonly app: App;
  readonly container: Element;
  /** The page's `Navigation.t` (`source` mode), once its first payload has rendered. */
  readonly started: Promise<unknown>;
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
  private readonly wrapped = new Map<unknown, unknown>();

  constructor(
    app: App,
    container: Element,
    act: (f: () => void) => void,
    start: (page: Page) => Promise<unknown>,
    shell: Promise<string>,
    firstRequest: number,
  ) {
    this.app = app;
    this.container = container;
    this.act = act;
    this.firstRequest = firstRequest;
    this.shell = shell;
    this.shell.catch(() => {});
    this.started = start(this);
    // A page that fails to start fails the test through `started`, not as an unhandled rejection.
    this.started.catch(() => {});
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
          await new Promise<void>((resolve) => held.push(resolve));
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

/**
 * Opens `url` in `container`: requests its HTML through the server, pushes the rows it carries as
 * the page's inline scripts would, and starts the client on them. In `build` mode, the client is
 * the build's own bootstrap, which can only be imported once per test file (its modules are
 * shared), so a build-mode test file opens one page, and moves on by following links.
 */
export function openPage(app: App, options: OpenOptions): Page {
  app.delivery = options.delivery ?? {type: 'immediate'};
  const self = globalThis as {__weft?: unknown};
  delete self.__weft;
  const push = (row: string | null) => {
    ((self.__weft ??= []) as {push: (row: string | null) => void}).push(row);
  };
  const firstRequest = app.requests.length;
  // Entrypoints' own requests (a form posting, say) go to the server too.
  (globalThis as {fetch: typeof fetch}).fetch = app.fetch as typeof fetch;
  const html = app.fetch(options.url, {headers: {Accept: 'text/html'}});
  const shell = html.then((response) => readPage(response.body!, push));
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
  if (app.mode === 'source') {
    return new Page(
      app,
      options.container,
      options.client.act,
      (page) =>
        options.client.start({
          loadModule: page.loader(options.client.loadModule),
          fetch: payloadFetch,
          container: options.container,
          url: options.url,
        }),
      shell,
      firstRequest,
    );
  }
  if (builtBootstrapImported) {
    throw new Error(
      '[weft] a build-mode test file can open one page (follow links from it)',
    );
  }
  builtBootstrapImported = true;
  const document = options.container.ownerDocument;
  if (
    options.container.id !== 'root' ||
    !document.body.contains(options.container)
  ) {
    throw new Error(
      "[weft] in build mode, the container is the document's #root",
    );
  }
  const window = document.defaultView as unknown as {
    history: History;
    fetch: typeof fetch;
  };
  window.history.replaceState(null, '', options.url);
  return new Page(
    app,
    options.container,
    options.client.act,
    async () => {
      const bootstrap = builtBootstrap(app.buildDir);
      await import(/* @vite-ignore */ bootstrap);
      return undefined;
    },
    shell,
    firstRequest,
  );
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
