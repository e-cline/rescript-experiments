# @e-cline/vite_plugin_weft

The Vite plugin for [Weft's server components](../weft_server): it runs the server entry in an `rsc`
environment and the browser's code in the `client` one, makes every entrypoint file a chunk of its
own, refuses to let client code import a server file, checks the app's RPC IDs are unique, answers
requests in development with the server entry, and builds both. This is phases 4 to 6 of
[the server components plan](../../docs/weft_server_components_plan.md).
[`examples/weft_split`](../../examples/weft_split) is an app using it.

## Setting it up

The plugin works on what `rescript build` writes, so the app has to compile through
[`ppx_weft`](../../tools/ppx/weft), which marks each compiled file with server components or
entrypoints with a directive (`'use weft server'`, `'use weft entrypoint'`), each server-only file
(`@@weft.server`) with the server one, and each RPC a file declares with `'use weft rpc <id>'`. In
`rescript.json`:

```json
{
  "ppx-flags": ["@e-cline/ppx_weft/ppx"]
}
```

Without it, `@weft.component` is ignored and every use of a component it marks is a type error about
`component<'a>`, which doesn't say why. The plugin checks for it, and stops with a message saying
what to add.

Then, in `vite.config.ts`:

```ts
import {weft} from '@e-cline/vite_plugin_weft';

export default {
  plugins: [weft({server: 'src/Server.res.js', client: 'src/Client.res.js'})],
};
```

- `server` is a compiled module whose default export is a fetch handler (`Request` to a promise of a
  `Response`), as an `@e-cline/servy` `App.t` is: `let default = app` in ReScript.
- `client` (optional) is the bootstrap, the module the page loads first. It renders the payload into
  the page, loading entrypoints with `virtual:weft/client`'s `loadModule`. By default it's
  `virtual:weft/bootstrap`, which runs `WeftServer.Bootstrap.main`: the first page's rows rendered
  into `#root`, navigation, and refetching the page when a server file changes in development.

`vp dev` serves the app; `vp build` writes `dist/client` (static files) and `dist/server/index.js`
(the handler), which `serve` from `@e-cline/vite_plugin_weft/node` runs:

```js
import {serve} from '@e-cline/vite_plugin_weft/node';

await serve({dir: 'dist', port: 3000});
```

## Virtual modules

| Module                           | Where  | What it is                                                                                                                                                                                                           |
| -------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `virtual:weft/client`            | client | `loadModule(id)`, the module of an entrypoint file, for `WeftServer.Decoder.make`; `onRefresh(listener)`, called when a server file changes in dev.                                                                  |
| `virtual:weft/bootstrap`         | client | The default bootstrap: `WeftServer.Bootstrap.main`, with `virtual:weft/client`'s `loadModule` and `onRefresh`.                                                                                                       |
| `virtual:weft/client-references` | client | Each entrypoint file's id, and a function `import()`ing it. The only files the client can be told to load.                                                                                                           |
| `virtual:weft/assets`            | server | `{scripts, preloads, styles, entrypoints, loadModule}`: the URLs a page loads the client with, each entrypoint file's chunk and the chunks it imports, and the server's `loadModule`, for rendering the page's HTML. |
| `virtual:weft/ssr-references`    | server | The reference map for the server: each entrypoint file, imported up front, and `loadModule`.                                                                                                                         |

Types for them are in `@e-cline/vite_plugin_weft/virtual`. A client environment importing
`virtual:weft/assets`, or the server one of the client modules, is an error.

## How it works

- **Entrypoint files are found by scanning.** `rescript build` has written every compiled file
  before Vite starts, so the plugin reads the app's `rescript.json` and its ReScript dependencies'
  (not dev sources), and picks out each compiled file with the entrypoint directive. Its id is the
  one `ppx_weft` gives it (the package's name, then the source's path in it), and the plugin checks
  that against the ids in the file's marks. Each file is `import()`ed from
  `virtual:weft/client-references`, so each is a chunk of its own, with whatever it alone imports.
- **RPC IDs** are collected by the same scan, from the `'use weft rpc <id>'` directives: an ID
  declared in two files (the app's, or a dependency's) fails the build and the dev server, naming
  both. (When `rescript build -w` changes a file's RPCs in development, the scan runs again, and
  fails the same way.)
- **The boundary.** A file with `'use weft server'` (server components, or `@@weft.server`) reaching
  the client environment is an error that names the chain of imports that got it there. In
  development that's the request for it; in a build, the build, once its module graph is complete.
  The directives are blanked out in both environments, so bundlers don't warn about them, and
  nothing else in the file moves.
- **Development.** After Vite's own middleware, every request goes to the server entry, imported
  through the `rsc` environment's module runner, so it always runs the current code.
  `@e-cline/js_env` is bundled into that environment rather than left to Node, so `Common.Env.isDev`
  is `true` there in development, as in the browser. When `rescript build -w` rewrites a file:
  - one only the server has: the client gets a `weft:refresh` event (`onRefresh`), to refetch the
    page's payload and render it over the old one, keeping entrypoints' state;
  - one the client has: a full reload (Weft has no fast refresh);
  - one that became, or stopped being, an entrypoint file: the reference map is made again, and the
    page reloads.
- **Building.** `vp build` builds the client first, with the bootstrap as its entry and the manifest
  on, then the server, whose `virtual:weft/assets` is made from that manifest.

## Testing an app

`@e-cline/vite_plugin_weft/testing`, with its ReScript bindings `WeftTesting`, tests an app the way
a browser uses it, without one:

```rescript
let app = await WeftTesting.start(~root=packageRoot) // or ~mode=Build, ~buildDir
let page = app->WeftTesting.open_(~container, "/notes/1")
await page->WeftTesting.waitFor(() => page->WeftTesting.has("#title"))
await page->WeftTesting.hydrated // a click before hydration is only replayed later
page->WeftTesting.click("#like")
let _ = await app->WeftTesting.callServer("tests/FakeDbControl.res.js", "release", [JSON.String("body:1")])
await page->WeftTesting.navigate("/notes/2")
```

- **The server runs in a worker thread**, its own realm, with no DOM: its modules come from the
  app's sources through a Vite server in the test (whose `rsc` environment's module runner is in the
  worker), or from a build. `callServer` calls a module of the server's, the same instance the app
  uses (a fake database's controls, say).
- **The page runs in the test's jsdom**, with the real bootstrap and the real reference map (the
  test's Vite config has the weft plugin, as the app's own does). Its first request is the HTML,
  applied as a browser's parser would, as it arrives (jsdom can't parse a stream): the shell into
  the container, which stands for `#root`, then each inline script (the rows pushed, boundaries
  swapped in) and segment, in order. The bootstrap starts once the shell is in, and hydrates it.
  Every request after that (payloads, refetches, an entrypoint's own `fetch`) goes to the worker
  too. A segment is found by its id in the whole document, so one page is open at a time.
- **The test decides when bytes arrive**: as they're sent, one chunk per `deliver`, or cut every _n_
  bytes. Cancelling a response (a navigation away) aborts the request in the worker.
- **What it checks**: `waitFor` a condition, `settle` until quiet, `loads` (and `holdLoads` to make
  a chunk slow), `renderCount` of an entrypoint, `snapshot` and `removedSince` (that an update kept
  the DOM's nodes), `pageRequests`. For hydration: `hydrated` waits for it, `htmlNodes` is what the
  HTML made (`removedSince` it is what hydration replaced), `warnings` what the console said, and
  `~bootstrap=false` (then `startBootstrap`) opens a page as if the bootstrap's chunk hadn't loaded.
  `rewriteBodies` changes requests on their way to the server, to play a client older or newer than
  it (an RPC's request with other fields), or a forged one.
- **`Build` mode** runs the build: the worker imports `dist/server/index.js`, and the page is the
  built client's own bootstrap and chunks. A file can open one page that way (the build's modules
  are shared), and moves on by following links.

[`examples/weft_notes`](../../examples/weft_notes) is tested this way, and
[`examples/weft_split`](../../examples/weft_split) in both modes.

## Testing the plugin

The tests run against small apps in [`tests/fixtures`](tests/fixtures): ReScript packages compiled
through the PPX by the workspace's build, with the output committed. A test copies one and builds
it, or changes its files as `rescript build -w` would:

- **Unit:** finding directives and blanking them out; the scan (dependencies, dev sources, ids,
  marks that disagree, RPC IDs and duplicates); and the generated modules.
- **Build:** a fixture built with `buildApp`: a chunk per entrypoint file, shared modules in shared
  chunks, a large client-only module only where it's used, no server code in the client, the
  manifest's URLs in the server's assets, the production export conditions, and `serve`. A fixture
  whose client imports a server file (an `@@weft.server` one) fails to build, naming the chain; so
  does one with an RPC ID declared twice, and one without the PPX.
- **Dev:** a dev server in the test process: pages and payloads through the middleware, the
  development conditions, the boundary error, an RPC ID declared twice, and the HMR messages for
  each kind of change.
- **The harness:** the fixture's server in the worker (no browser globals there, the development
  conditions, `callServer`, changed code running), chunks held and re-cut, and the HTML's rows read
  back however the HTML is cut.
