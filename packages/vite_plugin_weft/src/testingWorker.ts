// The server side of the test harness (`testing.ts`): a worker thread, so the app's server code
// has its own module instances and globals, and no DOM, as in production.
//
// In `source` mode its modules come from the harness's Vite server, through a module runner whose
// transport is this thread's port; in `build` mode it imports the server build. Either way it
// answers requests the client makes (streaming each response's body back), and calls into the
// server's modules for the test.
//
// It imports nothing of the plugin's own, so it can run from the source as well as the build.

import {pathToFileURL} from 'node:url';
import {parentPort, workerData} from 'node:worker_threads';

import {ESModulesEvaluator, ModuleRunner} from 'vite/module-runner';

/** What the harness starts the worker with. */
export type WorkerData =
  | {mode: 'source'; root: string; server: string}
  | {mode: 'build'; root: string; serverBuild: string};

/** Messages from the harness. */
export type ToWorker =
  | {type: 'hot'; payload: unknown}
  | {type: 'invoked'; id: number; result: unknown}
  | {
      type: 'request';
      id: number;
      method: string;
      url: string;
      headers: [string, string][];
      body: Uint8Array | null;
    }
  | {type: 'cancel'; id: number}
  | {type: 'call'; id: number; module: string; name: string; args: unknown[]}
  | {type: 'globals'; id: number; names: string[]};

/** Messages to the harness. */
export type FromWorker =
  | {type: 'ready'}
  | {type: 'failed'; message: string}
  | {type: 'invoke'; id: number; data: unknown}
  | {type: 'response'; id: number; status: number; headers: [string, string][]}
  | {type: 'chunk'; id: number; bytes: Uint8Array}
  | {type: 'end'; id: number}
  | {type: 'error'; id: number; message: string}
  | {type: 'called'; id: number; value?: unknown; error?: string};

const port = parentPort!;
const data = workerData as WorkerData;
const send = (message: FromWorker, transfer: ArrayBuffer[] = []) =>
  port.postMessage(message, transfer);

let invokes = 0;
const invoked = new Map<number, (result: unknown) => void>();
let onHot: ((payload: never) => void) | undefined;

const runner =
  data.mode === 'source'
    ? new ModuleRunner(
        {
          transport: {
            connect: ({onMessage}) => {
              onHot = onMessage as (payload: never) => void;
            },
            invoke: (payload) =>
              new Promise((resolve) => {
                const id = invokes++;
                invoked.set(id, resolve as (result: unknown) => void);
                send({type: 'invoke', id, data: payload});
              }) as never,
          },
          sourcemapInterceptor: false,
          hmr: {logger: false},
        },
        new ESModulesEvaluator(),
      )
    : undefined;

/** A module of the server's, as the app itself has it. */
function importModule(path: string): Promise<Record<string, unknown>> {
  return runner === undefined
    ? import(pathToFileURL(path).href)
    : (runner.import(path) as Promise<Record<string, unknown>>);
}

async function handler(): Promise<(request: Request) => Promise<Response>> {
  const module = await importModule(
    data.mode === 'source' ? data.server : data.serverBuild,
  );
  const handle = module.default;
  if (typeof handle !== 'function') {
    throw new Error(
      "[weft] the server entry's default export isn't a fetch handler",
    );
  }
  return handle as (request: Request) => Promise<Response>;
}

/** Each request still being answered, by id: aborting it cancels the body. */
const requests = new Map<number, AbortController>();

async function answer(message: Extract<ToWorker, {type: 'request'}>) {
  const controller = new AbortController();
  requests.set(message.id, controller);
  try {
    const handle = await handler();
    const response = await handle(
      new Request(message.url, {
        method: message.method,
        headers: message.headers,
        body: message.body as Uint8Array<ArrayBuffer> | null,
        signal: controller.signal,
      }),
    );
    send({
      type: 'response',
      id: message.id,
      status: response.status,
      headers: [...response.headers],
    });
    if (response.body !== null) {
      const reader = response.body.getReader();
      controller.signal.addEventListener('abort', () => {
        reader.cancel().catch(() => {});
      });
      for (;;) {
        const {done, value} = await reader.read();
        if (done || controller.signal.aborted) break;
        send({type: 'chunk', id: message.id, bytes: value});
      }
    }
    if (!controller.signal.aborted) send({type: 'end', id: message.id});
  } catch (error) {
    if (!controller.signal.aborted) {
      send({type: 'error', id: message.id, message: String(error)});
    }
  } finally {
    requests.delete(message.id);
  }
}

async function call(message: Extract<ToWorker, {type: 'call'}>) {
  try {
    const module = await importModule(message.module);
    const exported = module[message.name];
    if (typeof exported !== 'function') {
      throw new Error(
        `[weft] ${message.module} has no function ${message.name}`,
      );
    }
    const value = await (exported as (...args: unknown[]) => unknown)(
      ...message.args,
    );
    send({type: 'called', id: message.id, value});
  } catch (error) {
    send({type: 'called', id: message.id, error: String(error)});
  }
}

port.on('message', (message: ToWorker) => {
  switch (message.type) {
    case 'hot':
      onHot?.(message.payload as never);
      break;
    case 'invoked':
      invoked.get(message.id)?.(message.result);
      invoked.delete(message.id);
      break;
    case 'request':
      void answer(message);
      break;
    case 'cancel':
      requests.get(message.id)?.abort();
      break;
    case 'call':
      void call(message);
      break;
    case 'globals':
      // Which of these globals the server's realm has: none of the browser's, here.
      send({
        type: 'called',
        id: message.id,
        value: message.names.filter((name) => name in globalThis),
      });
      break;
  }
});

send({type: 'ready'});
