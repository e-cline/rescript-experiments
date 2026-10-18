# @e-cline/vite_plugin_weft

The Vite plugin for [Weft's server components](../weft_server): it runs the server entry in an `rsc`
environment and the browser's code in the `client` one, makes every entrypoint file a chunk of its
own, refuses to let client code import a server file, answers requests in development with the
server entry, and builds both. This is phase 4 of
[the server components plan](../../docs/weft_server_components_plan.md).
[`examples/weft_split`](../../examples/weft_split) is an app using it.

## Setting it up

The plugin works on what `rescript build` writes, so the app has to compile through
[`ppx_weft`](../../tools/ppx/weft), which marks each compiled file with server components or
entrypoints with a directive (`'use weft server'`, `'use weft entrypoint'`). In `rescript.json`:

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
- `client` is the bootstrap, the module the page loads first. It renders the payload into the page,
  loading entrypoints with `virtual:weft/client`'s `loadModule`.

`vp dev` serves the app; `vp build` writes `dist/client` (static files) and `dist/server/index.js`
(the handler), which `serve` from `@e-cline/vite_plugin_weft/node` runs:

```js
import {serve} from '@e-cline/vite_plugin_weft/node';

await serve({dir: 'dist', port: 3000});
```

## Virtual modules

| Module                           | Where  | What it is                                                                                                                                         |
| -------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `virtual:weft/client`            | client | `loadModule(id)`, the module of an entrypoint file, for `WeftServer.Client.make`; `onRefresh(listener)`, called when a server file changes in dev. |
| `virtual:weft/client-references` | client | Each entrypoint file's id, and a function `import()`ing it. The only files the client can be told to load.                                         |
| `virtual:weft/assets`            | server | `{scripts, preloads, styles, entrypoints}`: the URLs a page loads the client with, and each entrypoint file's chunk and the chunks it imports.     |

Types for them are in `@e-cline/vite_plugin_weft/virtual`. A client environment importing
`virtual:weft/assets`, or the server one of the client modules, is an error.

## How it works

- **Entrypoint files are found by scanning.** `rescript build` has written every compiled file
  before Vite starts, so the plugin reads the app's `rescript.json` and its ReScript dependencies'
  (not dev sources), and picks out each compiled file with the entrypoint directive. Its id is the
  one `ppx_weft` gives it (the package's name, then the source's path in it), and the plugin checks
  that against the ids in the file's marks. Each file is `import()`ed from
  `virtual:weft/client-references`, so each is a chunk of its own, with whatever it alone imports.
- **The boundary.** A file with `'use weft server'` reaching the client environment is an error that
  names the chain of imports that got it there. In development that's the request for it; in a
  build, the build, once its module graph is complete. The directives are blanked out in both
  environments, so bundlers don't warn about them, and nothing else in the file moves.
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

## Testing

The tests run against small apps in [`tests/fixtures`](tests/fixtures), whose "compiled ReScript" is
written by hand, so they need neither ReScript nor the PPX:

- **Unit:** finding directives and blanking them out; the scan (dependencies, dev sources, ids,
  marks that disagree); and the generated modules.
- **Build:** a fixture built with `buildApp`: a chunk per entrypoint file, shared modules in shared
  chunks, a large client-only module only where it's used, no server code in the client, the
  manifest's URLs in the server's assets, the production export conditions, and `serve`. A fixture
  whose client imports a server file fails to build, naming the chain; so does one without the PPX.
- **Dev:** a dev server in the test process: pages and payloads through the middleware, the
  development conditions, the boundary error, and the HMR messages for each kind of change.
