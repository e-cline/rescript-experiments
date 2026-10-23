# Plan: server components for Weft

Server components for Weft: components that run only on the server (and may be `async`), whose
output streams to the browser as a serialized element tree, with interactive components loaded on
demand, each in its own code-split chunk. It's modelled on React Server Components, but doesn't
follow the Flight protocol or try to cover everything it does.

Both kinds of component are marked explicitly:

```rescript
// src/NotePage.res -- runs only on the server
@@jsxConfig({version: 4, module_: "Weft.Jsx"})

@weft.component({kind: Server})
let make = async (~id: string) => {
  let note = await Db.note(id)
  <article>
    <h1> {Weft.Jsx.string(note.title)} </h1>
    <LikeButton noteId=id initial=note.likes />
    <Weft.Suspense fallback={<p> {Weft.Jsx.string("Loading comments...")} </p>}>
      <Comments noteId=id />
    </Weft.Suspense>
  </article>
}

// src/LikeButton.res -- an entrypoint: its code is loaded in the browser, in its own chunk
@@jsxConfig({version: 4, module_: "Weft.Jsx"})

@weft.component({kind: Entrypoint})
let make = (~noteId: string, ~initial: int) => {
  let (likes, setLikes) = Weft.Hooks.useState(() => initial)
  <button onClick={_ => setLikes(n => n + 1)}> {Weft.Jsx.int(likes)} </button>
}
```

A **shared** component is `@weft.component` with no argument (or a plain `@jsx.component`, as Weft
components are written today): it runs wherever it's rendered from (on the server inside a server
component's output, in the browser inside an entrypoint's).

`@weft.component` is Weft's own attribute, handled by a new PPX (§2), which turns it into
`@jsx.component` for ReScript's JSX transform. The compiler doesn't know it, so forgetting the PPX
is a compile error rather than a component that quietly does the wrong thing (verified point 2).

## Status

Phases 0--6 are done, on the branch `claude/weft-ppx-phase-0` (one commit or a few per phase; all
the phases will go in one PR, not opened yet). Next is phase 7, HTML rendering and hydration (§9),
which has a plan of its own: [`weft_ssr_hydration_plan.md`](weft_ssr_hydration_plan.md). Its phase
7.0 is done: the packages' sources sorted into `client/`, `server/` and `shared/`,
`WeftServer.Client` renamed `Decoder`, and `Rpc`'s server half split out as `RpcServer`; the names
here are the new ones.

| Phase | What                                                                | Where                                                          |
| ----- | ------------------------------------------------------------------- | -------------------------------------------------------------- |
| 0     | `ppx_weft` (attribute rename and checks), shared opam switch        | `tools/ppx/weft`, `tools/ppx/weft_tests`, `tools/ppx/setup.sh` |
| 1     | `Lazy`, `Entrypoint`, `ServerRender`, `Weft.Lazy`                   | `packages/weft_core`, `packages/weft`                          |
| 2     | async server components, entrypoint ids and directives              | `tools/ppx/weft`, `tools/ppx/weft_tests`                       |
| 3     | `Payload`, `Render`, `Client`, `Testing`; `Deferred`                | `packages/weft_server`, `packages/weft_core`                   |
| 4     | the Vite plugin, `serve`; the `weft_split` example                  | `packages/vite_plugin_weft`, `examples/weft_split`             |
| 5     | `Page`, `Bootstrap`, `Navigation`, `useRefetchable`; tier 2 harness | `packages/weft_server`, `packages/vite_plugin_weft`            |
|       | `weft_notes` (tier 2 scenarios, tier 3 browser tests)               | `examples/weft_notes`, `examples/weft_split`                   |
| 6     | Weft RPCs: `Rpc`, `Rpc.Codec`; `@weft.rpc`, `@@weft.server`; IDs    | `packages/weft_server`, `tools/ppx/weft`, the plugin           |
|       | `weft_notes`' changes as RPCs, `rewriteBodies` in the harness       | `examples/weft_notes`, `packages/vite_plugin_weft`             |

Where the implementation went its own way, the sections below say so. Things learned on the way, for
whoever picks this up:

- **After changing a PPX, rebuild what uses it from scratch** (`pnpm rescript:clean`, or touch the
  `.res` files): `rescript build` recompiles from changes to sources, not to the PPX executable, and
  stale output would otherwise be committed. A clean build reproducing the committed `.res.js`
  exactly is the check. (`rescript:clean` also removes `examples/react_ui`'s `.res.jsx`, which only
  `pnpm run build` restores.)
- **An async server component can't be rendered by the client reconciler**: every render calls it
  again and starts a new promise, a loop that runs in microtasks and starves even a test runner's
  timeout. Call it once and await it (as the server renderer does), or render it through `Render`.
- **Rows are flushed in a macrotask** after they're written, so a test waiting for the server's
  output needs a few `Testing.tick()`s, not one.
- **A synchronous child process can hang the test runner**: `tools/ppx/weft_tests` gives each `bsc`
  run a timeout. When running a suite by hand that might hang, put a time limit on it
  (`perl -e 'alarm 120; exec @ARGV' vp test run`).
- **`pnpm run test` can fail at random with `ENOTEMPTY` on `node_modules/.vitest-cache`** (parallel
  Vitest processes sharing the cache directory). Running it again passes; a cache directory per
  package would fix it.
- **Test components shouldn't pass `undefined` host props** (`title=?note`): the TestRenderer prints
  them as `title="undefined"`.
- **Compile ReScript with `vp run -w res`, not `npx rescript build`**: the bare command leaves out
  dev sources, and deletes every package's compiled tests.
- **Vite builds run from a Vitest test are development builds** unless `NODE_ENV` is set to
  `production` around them: Vitest sets it to `test`, and Vite picks the export conditions (and with
  them `Common.Env.isDev`) from it. The plugin's and `weft_split`'s build tests do this.
- **A server build leaves `node_modules` dependencies external** (`@rescript/runtime`), so it only
  runs where they resolve: `weft_split`'s test builds into its own `node_modules/.weft-split-test`,
  not a temporary directory.
- **A TypeScript test importing `vite-plus/test` fails in a ReScript package** under the root `vp`
  ("Vitest failed to find the runner"): the workspace has two copies of vite-plus 1.3.0 (different
  peer sets), the root `vp` runs its own Vitest, and the package's `vite-plus/test` is the other's.
  It passes when run with the package's own `vp`, and in `vite_plugin_weft` either way. ReScript
  tests, through `rescript-vitest`, are fine, so `weft_split`'s build test is `Build_test.res`, with
  the file and Vite work in a JavaScript helper (`BuildSupport.mjs`).
- **Rolldown doesn't know a module's importers yet in `transform`**: the plugin's build reports a
  client import of a server file at `buildEnd`, once the graph is complete.
- **The built client's shared code is in the bootstrap's chunk**, so importing an entrypoint's chunk
  runs the bootstrap: `weft_split`'s test does it under jsdom, with no `#root` for it to render into
  (`Bootstrap.main` does nothing then).
- **`vp run` loads every package's Vite config to make its task graph**, and an example's config
  imports the plugin's `dist`: a stale or broken `dist` fails every `vp run`, even the plugin's own
  build. `npx vp pack` in `packages/vite_plugin_weft` breaks the loop.
- **jsdom's `click()` doesn't move the focus**, and a browser's does: a browser test that checks
  focus submits a form with Enter, not by clicking its button.
- **A page streams for as long as its gates are closed**, so the harness's `settle` can't wait for
  responses to end: tests `waitFor` what they expect, and `settle` waits for quiet.
- **Vite+'s formatter wraps TypeScript at 80 columns** (ReScript and Markdown at 100).
- **When breaking code on purpose to see a test catch it, check the build succeeded**: a change that
  doesn't compile leaves the last compiled `.res.js` in place, and the tests pass against that.
- **Don't find things in compiled output by the names ReScript gives imports**: a module of another
  package is imported as `Rpc$WeftServer`, not `WeftServer__Rpc`, and a small function of another
  module can be inlined. What the plugin reads, the PPX writes as a directive
  (`'use weft rpc <id>'`), which bsc writes verbatim at the top of the file.
- **An RPC's declaration needs its type written out**: nothing in `Rpc.make(...)` fixes the response
  or error types, so they're weak type variables, which a module can't export.
- **`@@` in an OCaml format string is an escaped `@`**: an error message naming `@@weft.server`
  through `Location.raise_errorf` writes it `@@@@weft.server`.

## What was verified before writing this

Checked against ReScript 12.3.1 (the version this workspace pins) in a scratch project, with a
throwaway ppxlib probe built from the existing `ppx_pretty_print` opam switch:

1. **`@weft.component(kind=Server)` would be a syntax error** ("Did you mean `==` here?"): an
   attribute's argument has to be an expression. `@weft.component({kind: Server})` and
   `@weft.component(Server)` both parse. This plan uses the record form, which leaves room for more
   options later (`{kind: Entrypoint, preload: false}`).
2. **Without the PPX, `@weft.component` is silently ignored, and any use fails to compile.** The
   compiler doesn't complain about an attribute it doesn't know, but the JSX transform doesn't touch
   the function either, so `make` has no `props` type and `<LikeButton ... />` is a type error
   (`(~x: string) => element` where `component<'a>` was expected). The message isn't clear, but
   nothing builds, so it can't go unnoticed. (Putting the kind on `@jsx.component` instead would
   have been worse: the built-in transform ignores an argument there, so without the PPX an
   entrypoint would compile as an ordinary component.)
3. **An external PPX runs before the built-in JSX transform**, and its output is what the transform
   sees. The probe, listed in `ppx-flags`, received the attribute and its argument intact
   (`[@@weft.component { kind = Entrypoint }]`, no generated `props` type yet). A version that
   renamed `weft.component` to a plain `jsx.component` compiled a component used from another file,
   in both a `.res` and its `.resi`, to exactly what `@jsx.component` gives.
4. **The PPX gets the source file's absolute path** (`pos_fname`), so it can name entrypoints by
   file. Absolute paths can't go into the output (the compiled JS is committed, and must be the same
   in every checkout), so ids are made relative to the package root (see §3).
5. **`async` components don't work with a custom JSX module.** The transform wraps an async `make`
   in a hard-coded `Jsx.promise(...)` (the standard library's `Jsx`, not the configured module), so
   with `WeftDom.Jsx` it fails: `promise<MyJsx.element>` vs `promise<Jsx.element>`. The PPX has to
   rewrite `async` server components itself (§2), before the transform sees them.
6. **`import(File.make)`** (ReScript 12's replacement for the deprecated `Js.import`) compiles to
   `import("./File.res.js").then(m => m.make)`, but only for a **file-level** value:
   `import(File.Nested.make)` is rejected ("Dynamic import requires a module or module value that is
   a file"). So the client's lazy imports are generated in JavaScript by the Vite plugin, which can
   reach `m.Nested.make`, not written in ReScript.
7. **`@@directive("...")` writes its string verbatim** as the file's first line: `@@directive("x")`
   gives a bare `x`, so a directive needs its own quotes: `@@directive("'use weft entrypoint'")`.
   That's what the PPX uses to mark files for the Vite plugin (§4).
8. **Package-level `ppx-flags` work in the root build** (`examples/pretty_print` already relies on
   it), so only the packages using server components need the new PPX.
9. **`Weft.Jsx` loads without a DOM.** `Weft` is only aliases (its compiled module is empty), so
   `Weft.Jsx` compiles to an import of `WeftDom.Jsx`, whose module imports only `WeftCore.JsxCore`.
   So server components can build host elements with it on the server.
10. **The bundled Vite (`vite-plus-core` 1.3.0) has the Environment API** (`buildApp`,
    `createRunnableDevEnvironment`, `createServerModuleRunner`), which the plugin is built on.

## How it works, end to end

```
 server (Vite "rsc" environment)                     browser (Vite "client" environment)
 ───────────────────────────────                     ───────────────────────────────────
 request ──> route handler                           bootstrap chunk (virtual:weft/client)
              │                                        │
              ▼                                        ▼
 WeftServer.Render.toStream(<NotePage id />)         WeftServer.Decoder.fromStream(rows)
   walks the tree:                                     decodes rows into elements:
   - server/shared components: called                  - host elements, Suspense: as they are
   - host elements: serialized                         - entrypoint refs: import() the chunk,
   - entrypoints: a reference + their props              row blocked until it's loaded
   - async / suspended under <Suspense>:               - lazy rows: WeftCore.Lazy elements,
     a placeholder now, a row later                      resolved as rows arrive
              │                                        │
              └──── rows, streamed in the HTML ───────>│
                    (or a fetch, on navigation)        ▼
                                                     WeftDom.Client root renders, and
                                                     re-renders as each row lands
```

The client never receives server components' code: only their output, and references to the
entrypoints in it, which load on demand.

## Design

### 1. Component kinds

| Kind       | Marked                                        | Runs                                | May                                                       |
| ---------- | --------------------------------------------- | ----------------------------------- | --------------------------------------------------------- |
| Server     | `@weft.component({kind: Server})`             | server only                         | be `async`; read server-only modules; render any kind     |
| Entrypoint | `@weft.component({kind: Entrypoint})`         | browser (and, with SSR, the server) | use every hook; take only serializable props              |
| Shared     | `@weft.component` (or plain `@jsx.component`) | wherever it's rendered from         | use `Hooks.use` anywhere; other hooks only in the browser |

Rules, enforced where noted:

- **A file is server or client, not both.** A file defining a server component may not define an
  entrypoint (PPX error), and the client environment refuses to import a file with server components
  (Vite plugin error, naming the import chain).
- **Entrypoint props are serializable**: strings, numbers (including `NaN`, infinities and `-0`),
  booleans, `bigint`, `null`/`undefined`, arrays, plain objects (so records, variants, options,
  dicts and tuples as ReScript represents them), `Date`, elements, and promises of any of these
  (streamed: §5). Functions and class instances are not. A development build of the server renderer
  fails with the component, the prop and the path to the bad value; a production build with a
  numbered error, as `weft_core`'s errors are. The PPX also rejects a labelled argument whose
  written type is a function (`~onSave: string => unit`), which catches the common mistake at
  compile time, but it can't see through type aliases.
- **Host elements rendered on the server can't have event handlers or refs.** Same error, with a
  hint to move the element into an entrypoint.
- **Stateful hooks don't run on the server.** Server and shared components rendered by the server
  renderer have no fiber; the renderer calls them through `WeftCore.ServerRender.run`, which sets a
  "rendering on the server" flag in `HookImpl` (and sets aside any client render in progress) so
  `useState`, effects, `useContext` and the rest fail with a message saying so (rather than "called
  outside a component"). `Hooks.use(promise)` works: it suspends the component, which the server
  renderer retries once the promise settles (§5).
- **No context providers, error boundaries or portals in server output** (each fails with a message
  saying to render it in an entrypoint): providers' values and boundaries' fallbacks are client-side
  things, and a portal's container is a client object.
- **No context on the server**, as in React. Request data reaches server components as props. (A
  server-side context stack would be easy in a tree walk, but it isn't needed for a first version.)

### 2. The PPX (`tools/ppx/weft`, `@e-cline/ppx_weft`)

An OCaml ppxlib rewriter, built the same way as `ppx_pretty_print`. It handles `@weft.component`,
replacing it with `@jsx.component` for the JSX transform that runs after it (verified point 3), and
leaves everything else alone, `@jsx.component` included. So the core and DOM packages, and
client-only apps, keep compiling without it.

For `@weft.component` with no argument (a shared component), that replacement is all it does.

For `@weft.component({kind: Server})`:

```rescript
// written
@weft.component({kind: Server})
let make = async (~id: string) => {
  let note = await Db.note(id)
  <Note note />
}

// what the JSX transform then sees
@@directive("'use weft server'")
@jsx.component
let make = (~id: string) =>
  WeftCore.Lazy.fromPromise(
    (async () => {
      let note = await Db.note(id)
      <Note note />
    })(),
  )
```

- `@weft.component({kind: Server})` becomes a plain `@jsx.component`.
- An `async` function becomes a synchronous one returning a `WeftCore.Lazy` element (§6) around the
  body's promise. That sidesteps the transform's hard-coded `Jsx.promise` (verified point 5), and
  the component's type is an ordinary `component<props>`. A non-async server component is left
  alone.
- The file gets `@@directive("'use weft server'")`, once.

For `@weft.component({kind: Entrypoint})`:

```rescript
// src/Likes.res, written
module LikeButton = {
  @weft.component({kind: Entrypoint})
  let make = (~noteId: string, ~initial: int) => ...
}

// what the JSX transform then sees
@@directive("'use weft entrypoint'")
module LikeButton = {
  @jsx.component
  let make = (~noteId: string, ~initial: int) => ...
  let () = WeftCore.Entrypoint.mark(make, "@e-cline/weft_notes_example/src/Likes.res#LikeButton")
}
```

- The `let () = mark(...)` goes right after the binding, so it refers to the `make` the JSX
  transform defines last (the props-taking wrapper `jsx` receives), and sets a hidden
  `$$weftEntrypoint` property on it, like `Marker`'s `$$fiberKind`. It returns nothing and keeps the
  function's identity.
- The id is `<package name>/<source path from the package root>#<module path>`: the PPX walks up
  from `pos_fname` to the nearest `rescript.json` for both. The module path is empty for a
  file-level `make` (`...Likes.res#`), so the client looks up `m.make`; otherwise
  `m.LikeButton.make`.
- The file gets `@@directive("'use weft entrypoint'")`.

Errors (as ppxlib `Location.raise_errorf`, so they're ordinary compile errors at the right place):
an unknown `kind` or an argument that isn't `{kind: ...}`, `@weft.component` on anything but a `let`
binding of a function (or, in an interface, a `let` declaration), `@weft.component` and
`@jsx.component` on the same binding, `async` on anything but a server component, server components
and entrypoints in one file, and a function-typed labelled argument on an entrypoint. In an
interface file the PPX only replaces the attribute: the signature of a rewritten async server
component is already `(~id: string) => element`. (An interface still needs its own `@@jsxConfig`
line, as it does today.)

**Why a PPX rather than a function call?** Without one, an entrypoint could be written
`let make = WeftCore.Entrypoint.mark(make, ~id="...")` by hand, with the id kept in sync with the
file's path by convention. The PPX makes the id impossible to get wrong, gives every kind the same
`@weft.component` marking, and is needed anyway for `async`.

**Toolchain.** The two PPXs need the same OCaml and ppxlib (the ReScript AST pins ppxlib 0.34, which
needs OCaml < 5.4), so rather than a second opam switch that compiles OCaml again (decided: see
"Decisions"), move `setup.sh` and the lock file up to `tools/ppx/`, rename the switch to something
shared (`rescript_ppx`), and have both packages' `build` tasks use it. `setup.sh` runs as a root
task, `ppx:setup`, that both builds depend on, so two builds never install into the switch at once.
That also means updating `.vscode/settings.json`'s `ocaml.sandbox`, the CI opam cache key, and the
root `res` task's `dependsOn`, which gains `@e-cline/ppx_weft#build`.

### 3. Entrypoint ids and the client manifest

The client needs a way from an id to code. The plugin generates `virtual:weft/client-references` for
the client environment:

```js
export default {
  '@e-cline/weft_notes_example/src/Likes.res': () => import('/src/Likes.res.js'),
  // one line per file with the 'use weft entrypoint' directive
};
```

Each `import()` is its own chunk (Vite splits on dynamic imports). The client splits an id at `#`,
imports the file and walks the module path to the `make`. The browser only ever loads files in this
map, so a server can't make it load arbitrary URLs.

Files are found by **scanning the compiled output** for the directive: `rescript build` has already
written every `.res.js` before Vite starts, so a walk over the app's sources (and its ReScript
dependencies', found as ReScript finds them, through `node_modules`; dev sources left out) is simple
and deterministic, and doesn't need a server build first. The plugin makes each file's id as the PPX
does (the nearest `rescript.json`'s `name`, then the source's path), and checks it against the ids
in the file's `Entrypoint.mark` calls, so the two can't silently disagree. The cost is that an
entrypoint no server component renders still gets a chunk, which is harmless. (React's plugin
instead builds the server graph first to find client references; that can come later if it's ever
needed.)

ReScript renames modules that clash with JavaScript globals in its output (a module `Error` is
exported as `$$Error`, which phase 0's fixtures pin). The id keeps the ReScript module path
(`...#Error`), and the client, walking it, looks up each name and then the `$$`-prefixed one.
Copying ReScript's list of renamed names into the PPX instead was considered and dropped: it's long,
and the compiler can change it, while trying both names can't go wrong (a module can't export both
`Error` and `$$Error`).

### 4. The Vite plugin (`packages/vite_plugin_weft`, `@e-cline/vite_plugin_weft`)

TypeScript, on the Environment API (Vite 8, through Vite+). Configured with the server entry (a
module whose default export is a fetch handler, as `@e-cline/servy`'s `App.t` is:
`let default = app`) and the client bootstrap:

```ts
// examples/weft_split/vite.config.ts
plugins: [weft({server: 'src/Server.res.js', client: 'src/Client.res.js'})],
```

`client` is optional: by default the bootstrap is `virtual:weft/bootstrap`, which calls
`WeftServer.Bootstrap.main` with `virtual:weft/client`'s `loadModule` and `onRefresh` (phase 5; in
phase 4 the bootstrap had to be the app's own). An app with its own bootstrap imports what it needs
from `virtual:weft/client`.

What it does:

- **Two environments**: `rsc` (Node; runs server components) and `client` (browser). React's plugin
  needs a third, `ssr`, because React has a separate build for server components (the `react-server`
  condition); Weft's runtime is the same everywhere, so HTML rendering (phase 7) runs in `rsc` too.
- **Virtual modules**:
  - `virtual:weft/client-references` (client): the map in §3.
  - `virtual:weft/client` (client): what a bootstrap needs from the plugin: `loadModule` (from the
    map), and `onRefresh`, for the server HMR event. The bootstrap reads the rows the HTML stream
    delivers, creates a `WeftDom.Client` root and renders into it, and wires up navigation (§7).
  - `virtual:weft/assets` (rsc): `{scripts, preloads, styles, entrypoints}`: the module scripts to
    load (in dev, `/@vite/client` and the bootstrap), the bootstrap's imports (for `modulepreload`
    links) and stylesheets, and, for each entrypoint file, its chunk and the chunks it imports. In
    dev these are `/src/...` URLs; in a build, they come from the client build's `manifest.json`.
  - A client environment importing `virtual:weft/assets`, or the server one the client modules, is
    an error. "Client" is any environment but `rsc` (the browser's, and a Vitest test's, which the
    harness relies on); the boundary check applies to all of them too.
- **Enforcing the boundary.** A module with the `'use weft server'` directive reaching the client
  environment's `transform` is an error, naming the chain of imports from the entry to it: in dev at
  once (the module graph knows who asked for it), in a build at `buildEnd` (Rolldown only knows a
  module's importers once the graph is complete). Both directives are blanked out in `transform`
  (bundlers warn about module-level directives they don't understand); replacing them with spaces
  keeps every position, so no source map is needed. A server-only module with no server components
  has no directive, so nothing stops the client importing it; the build test's sentinel is what
  checks that.
- **The harness** (§10) supplies its own `rsc` environment, whose module runner is in a worker: the
  plugin keeps a `createEnvironment` the config already has, adds no middleware for an environment
  it can't run itself, and exposes its options (`api.options`) so the harness can find the server
  entry.
- **A missing PPX** is caught early: if the app's `rescript.json` doesn't list `ppx_weft` in its
  `ppx-flags`, the plugin stops with a message saying what to add (and what the compiler's error
  without it looks like).
- **Dev server.** `appType: 'custom'`, and a middleware, after Vite's own, passes requests to the
  server entry through the `rsc` environment's module runner (`@hono/node-server`'s
  `getRequestListener` turns the fetch handler into a Node listener), so a request always runs the
  current code. ReScript compiles in its own process (`vp run -w res:watch`), so changes arrive as
  `.res.js` writes:
  - a server-only module changed: send a custom HMR event, and the bootstrap refetches the current
    page's payload and renders it in a transition, keeping client state, like React's server HMR;
  - a client module changed: a full reload (Weft has no fast refresh);
  - a file became an entrypoint file, or stopped being one (or one was deleted): the scan is redone,
    the reference map and assets invalidated, and the page reloaded.
- **Build** (`buildApp`): the client first, then `rsc`, whose `virtual:weft/assets` reads the client
  manifest. The client's one entry is the bootstrap: the entrypoint files are chunks because
  `virtual:weft/client-references` `import()`s each, which also keeps all their exports (making them
  entries too, as first planned, wasn't needed). Output: `dist/client/` (static files) and
  `dist/server/index.js` (the handler). `serve` (in `@e-cline/vite_plugin_weft/node`) runs both,
  `dist/client` as static files (not the manifest) and the rest through the handler; the example's
  `start` task uses it.
- **Conditions.** `@e-cline/js_env`'s development/production export conditions (which
  `Common.Env.isDev` relies on) have to apply in the `rsc` environment as well as the client. Vite's
  server environments already resolve with them, but leave dependencies in `node_modules` to Node,
  which would always pick production, so the plugin makes `@e-cline/js_env` `noExternal` there.

### 5. The wire format and the server renderer (`packages/weft_server`)

A new ReScript package, namespace `WeftServer`, depending on `weft_core` and nothing
server-specific: `Render` produces a Web `ReadableStream<Uint8Array>`, which `@e-cline/servy`'s
`Respond.stream` (or any fetch-style server) can send. `Client` is browser-safe and shares the
format module, `Payload`.

**Rows.** A payload is newline-separated rows, `<id>:<tag><json>`. Row `0` is the root.

| Tag | Row                                                                                            |
| --- | ---------------------------------------------------------------------------------------------- |
| `J` | a value (an element tree, or a prop's resolved value)                                          |
| `E` | an entrypoint reference: `{"id": "<package>/src/Likes.res#LikeButton"}`, one per id per stream |
| `X` | an error: `{"digest": "...", "message": "..."}` (the message in development only)              |

Inside a `J` row's JSON, strings starting with `$` are special (and a literal one is written `$$`):

| Encoding                                                                 | Meaning                                                                                                                              |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `["$", type, key, p]`                                                    | an element: `type` is a tag name, `"$E3"` (the entrypoint in row 3), `"$S"` (`Suspense`) or `"$F"` (a keyed fragment); `p` its props |
| `"$L5"`                                                                  | an element that isn't ready: row 5 will have it                                                                                      |
| `"$@5"`                                                                  | a promise, resolved by row 5 (rejected, if row 5 is an `X`)                                                                          |
| `"$u"`, `"$n12"`, `"$NaN"`, `"$Inf"`, `"$-Inf"`, `"$-0"`, `"$D2026-..."` | `undefined`, `12n`, the special numbers, a `Date`                                                                                    |

Text and lists are JSON strings and arrays as they are. Shared references and cycles aren't
preserved (a cycle is an error); that keeps the encoder a plain recursive walk.

**Rendering.** `Render.toStream(element, ~onError=?, ~signal=?)` walks the tree, with no fibers:

- Server and shared components are called with their props, and their result walked. A keyed one's
  output is wrapped in a fragment with its key (`["$", "$F", key, {children}]`), as React does: the
  component leaves no fiber on the client to carry its key, and without this a list of keyed server
  components would lose its keys. A component that keeps suspending on a new promise every call is
  given up on after 100 tries, with an error.
- Host elements and their props are serialized (with the checks in §1).
- An entrypoint element (its `make` has `$$weftEntrypoint`) becomes `["$", "$E3", key, props]`, with
  an `E` row the first time that id appears. Its props, including any element children, are walked
  like everything else: server components passed as `children` render on the server.
- A `Lazy` element (an async component's result) or a component that throws `Suspended(promise)`
  (from `Hooks.use`) is **waited for** unless a `Suspense` element is above it in the server tree.
  Under a `Suspense`, it's written as `"$L5"` and the walk carries on; when the promise settles, the
  component is retried (or its result walked) and row 5 is written. Waiting outside a boundary
  rather than streaming a placeholder means **`Suspense` boundaries are the unit of streaming**, and
  a client that renders row 0 never suspends without a boundary to catch it.
- Independent async work under different boundaries runs concurrently, since the walk doesn't stop
  for any of it. Rows are written in the order they finish, batched per macrotask.
- A promise passed as an entrypoint prop becomes `"$@5"` straight away and row 5 is written when it
  settles, so a server component can start a fetch and hand the unfinished result to a client
  component, which reads it with `Hooks.use`.
- An exception in a component under a `Suspense` becomes an `X` row in place of that row (the client
  throws it there, for an `ErrorBoundary`); outside every boundary, it fails the root. `onError`
  sees every one and returns the digest, as React's does. `signal` aborting, or the client
  cancelling the stream (it went away), stops everything pending: nothing more is written, and
  components waiting on promises aren't called again.
- Elements are recognized in values by their shape (a plain object with exactly `kind`,
  `elementType`, `key` and `props`), since `weft_core`'s elements carry no brand. A record of the
  same shape would be taken for one.

### 6. The client decoder, and `WeftCore.Lazy`

`let client = WeftServer.Decoder.make(~loadModule, ~fetch=?)` makes a client, and
`client->Client.fromStream(stream) : promise<Element.t>` resolves with row 0's element once it's
decodable, and keeps decoding as rows arrive. `loadModule` (a file id, the part of an entrypoint id
before `#`, to a promise of the compiled file's module) is what the bootstrap fills in from
`virtual:weft/client-references`; `fetch` (a URL to a payload stream) defaults to the global
`fetch`. Taking both as arguments is also what lets tests run without Vite or a network (§10).
`client->Client.fetchElement(url)` fetches and decodes; `Client.Latest` runs fetches that replace
each other (the newest cancels the one before, and only its element is returned), which `navigate`
and `useRefetchable` use.

- Each row is a `WeftCore.Deferred`: a promise settled from outside, whose outcome `Hooks.use` and
  `Lazy` can read the moment it's settled (an ordinary promise's outcome is only known a microtask
  later, so a render right after a row arrived would suspend once for nothing). A row is created
  when it's first referred to or first arrives. Once the stream has ended, a row that never arrived
  fails, including one first referred to afterwards (by a row decoded late, after its entrypoints
  loaded).
- An `E` row starts its `import()` immediately. A `J` row that refers to an entrypoint isn't turned
  into elements until that module has loaded (Flight's "blocked" chunks), so an entrypoint element's
  type is always the component's real `make`, never a loader wrapper. That matters for refetching:
  the same entrypoint in the same place in the next payload is the same type, so the reconciler
  keeps its state.
- `"$L5"` becomes a `WeftCore.Lazy` element around row 5's promise. `"$@5"` becomes the promise
  itself. `"$S"` becomes a `WeftCore.Suspense` element; host types become `JsxCore.hostJsx`
  elements. Children that arrive as a list are passed on as `jsxs` marks static children, since they
  were written out in the server's JSX: no missing-key warnings for server output (duplicate keys
  are still reported).

**`WeftCore.Lazy` is the one change the reconciler needs.** A new `Element.kind`, `Lazy`, holds a
promise of an element (`Lazy.fromPromise`). The child reconciler unwraps it before comparing types:
a settled one is reconciled as the element it resolved to, in its place, with no fiber of its own; a
pending one throws `Suspended(promise)` from the parent's render, which the existing Suspense
machinery handles. Unwrapping rather than giving it a fiber is what keeps state across refetches: an
item that streamed in as a placeholder the first time and arrives complete the next time is still
the same element type at the same position. (React's `lazy` is unwrapped the same way.) It's useful
beyond server components, too: a client-only app can code-split a component by wrapping an
`import(Chart.make)` in one. The server renderer sees `Lazy` elements as well: they're what async
server components return.

A rejected lazy is replaced, as it's resolved, by an element that throws its error when rendered, so
the error comes from the lazy's own position: every boundary above it catches it, including an
`ErrorBoundary` whose direct child it is (thrown from its parent's render, it would be out of that
boundary's reach). React 19 does the same. A lazy that hasn't settled still suspends from its
parent's render, which the Suspense machinery is built around.

### 7. Pages, streaming, navigation and refetching

**The first request** (before phase 7's HTML rendering) gets one streamed HTML response: the
document shell, `<div id="root">`, the bootstrap `<script type="module" async>` (`async`, or it
would wait for the whole document) and `modulepreload` links, then the payload's rows as they're
produced, each as an inline `<script>(self.__weft||=[]).push("...")</script>` (`<` written as
`\u003c`, and the line separators escaped, so nothing in a row can end the script), with a
`modulepreload` for an entrypoint's chunk before the first row using it, until the payload ends
(`push(null)`). The bootstrap drains `__weft` and listens for more, so rows that arrive before or
after it loads are both handled, and there's one request, not a page then a fetch. The page shows
nothing until the bootstrap and row 0 are in, but everything under a `Suspense` boundary streams in
after that.

**Navigation** fetches the same route with `Accept: text/x-weft-payload`, which the server answers
with the bare payload, and renders the result into the root inside `Transition.start`: the old
screen stays until the new tree can render (Suspense phase c), entrypoints in the same place keep
their state, and the reconciler only touches what changed. As built, it's `WeftServer.Navigation`
(not functions in `Client`, which it builds on): a page (`Navigation.t`) made over any renderer,
with `navigate(url)`, `load(url)` (no history entry), `refresh()`, and `useNavigation()` for
entrypoints, provided by a context around what it renders. `Bootstrap.start` makes the browser's,
with `history.pushState` after a navigation and `popstate` loading the URL gone back to; links are
the app's own entrypoints calling `navigate` (`weft_notes`' and `weft_split`'s `Link`). They use a
`fetch` the client is created with (the global one, from the bootstrap), so a test can give it one
that goes to a stubbed server instead (§10).

`WeftServer.Page.respond(request, element, ~assets)` picks HTML or payload from the `Accept` header,
and stops rendering when the request is aborted. It takes and returns `@rescript/webapi`'s
`Request.t` and `Response.t`, as `@e-cline/servy` does, so `weft_server` depends on that package
(the renderer and the client still don't use it).

**In-place updates.** A refetch is never a remount: the new payload is decoded into ordinary
elements and rendered over the old ones, so the reconciler patches the screen as it would for any
client update, as React does. Concretely, for an element in the same position with the same key and
type in both trees:

- a host element keeps its DOM node (and with it focus, selection and scroll position), and only the
  attributes and text that changed are written;
- an entrypoint keeps its fiber and its state, and renders again with the new props;
- the rules for what does remount are the reconciler's usual ones (a different type or key at that
  position), applied to the tree _after_ the server components have run. Server components leave no
  fibers behind, so changing which server component produced some output doesn't remount it; only
  the output's own shape counts.

Three things in the decoder make that hold. Entrypoint modules are cached per client, not per
stream, so every payload's `make` for an id is the same function (and so the same type). Keys are
part of the encoding, so keyed lists reorder in place. And a row that has already arrived is marked
settled (`$$fiberStatus`) as soon as it's decoded, so a refetch's `Lazy` elements whose rows came in
the same chunk never suspend; without that, `Hooks.use`'s "suspend the first time" rule would make
every refetch abandon its render once.

The update is rendered in a transition, so boundaries already on screen don't fall back to their
fallbacks while the new payload streams in: the old content stays until the new content under it is
ready (Suspense phase c). Boundaries that are new in the payload show their fallbacks as usual.
Requests are numbered: a response that arrives after a newer one for the same place is dropped, and
its stream cancelled. What the cancelled payload hadn't delivered yet is left waiting, not failed:
it may still be on screen (under a fallback) until the newer payload has rendered, and failing it
would throw there. Only its root row fails, so whoever awaited it is told.

**Refetching part of the page.** A whole-page `refresh()` is the simple case. For a part of it, an
entrypoint uses `WeftServer.Navigation.useRefetchable(~src, children)`: given `children` rendered on
the server (as any element prop is), it returns the element to show, `refetch` and `isPending`.

```rescript
// in a server component: the comments, rendered here, given to an entrypoint as children
<CommentsPanel noteId=id> <Comments noteId=id /> </CommentsPanel>

// in CommentsPanel, the entrypoint
let comments = WeftServer.Navigation.useRefetchable(~src=`/notes/${noteId}/comments`, children)
<div>
  <button onClick={_ => comments.refetch()->ignore}> {Weft.Jsx.string("Reload")} </button>
  {comments.element}
</div>
// comments.isPending is true until the new subtree has rendered
```

It shows its `children` until it's refetched, then fetches `src` (or a URL `refetch` is given) as a
payload, and shows that element in their place, in a transition, under the same rules. The route at
`src` renders just that subtree, with `Page.respond`. Doing this by hand with `useState` and
`fetchElement` gets three things wrong easily, which the hook does: newer `children` from a later
`refresh()` or `navigate` win over what was refetched (state initialised from a prop would ignore
them), a refetch cancels the one before (a slow response can't land after a newer one), and the
render is a transition (boundaries don't flash their fallbacks, and `isPending` covers the fetch as
well as the render). Underneath is `WeftServer.Decoder.fetchElement(url)`, a promise of a decoded
element, for anything the hook doesn't cover.

As first planned and built in phase 5, this was `WeftServer.Frame`, a built-in entrypoint a server
component wrapped around a subtree, which entrypoints anywhere on the page refetched by name
(`useFrame("comments")`, through a page-wide registry). Reviewing phase 5, the names (which collide,
and whose registry leaked into the public interface) went first, leaving `Frame` a thin entrypoint
over `useRefetchable` found through context, and then `Frame` itself: an app's own entrypoint around
the part it refetches says what it does more plainly, and needs no hand-marked built-in entrypoint
in every app's reference map.

**Keys.** A list a server component builds at runtime (`Jsx.array`) and one written out in JSX look
the same once they've been through the payload, so the client marks every list it decodes as written
out (`JsxCore.markStaticList`, new in `weft_core`), and the server warns instead, in development,
about a runtime list of children with elements missing keys, naming where it is.

### 8. Weft RPCs (phase 6)

What other frameworks call server functions or server actions: functions that run on the server,
which the client calls as if they were local. Weft's are explicit, as TanStack Start's
`createServerFn` is and React's `'use server'` isn't: each has an ID its author chose, typed input,
response and error, and an optional client-side step before anything is sent. In the abstract, an
RPC is

```rescript
'input => promise<result<'response, WeftServer.Rpc.error<'error>>>
```

and the promise doesn't reject: every way a call can fail is an `Error`.

**An RPC is declared in one place and handled in another.** The declaration is shared code (the
client imports it): the ID, how a request goes over the wire, and what to do on the client first.
The handler is server code, in a server-only file, typed against the declaration:

```rescript
// src/Api.res: shared
type addComment = {noteId: string, author: string, text: string}

@weft.rpc({id: "notes.addComment"})
let addComment: WeftServer.Rpc.t<CommentForm.values, addComment, Types.comment, Errors.comment> =
  WeftServer.Rpc.makePrepared(
    // How a request is written on the client, and read (and checked) on the server.
    ~request=Codec.object3(
      ("noteId", Codec.string), ("author", Codec.string), ("text", Codec.string),
      (noteId, author, text) => {noteId, author, text},
      ({noteId, author, text}) => (noteId, author, text),
    ),
    // On the client, before sending: turn the caller's input into a request, or refuse (nothing
    // is sent). Can be async.
    ~prepare=async values =>
      switch String.trim(values.text) {
      | "" => Error(Errors.EmptyComment)
      | text => Ok({noteId: values.noteId, author: values.author, text})
      },
    // Checked on both sides: on the client for quick feedback, and again on the server, which
    // can't trust the client to have.
    ~check=request => String.length(request.text) > 2000 ? Error(Errors.TooLong) : Ok(),
  )

// src/ApiServer.res: server only (the attribute makes the client build refuse it, see below)
@@weft.server

let addComment = WeftServer.RpcServer.handler(Api.addComment, async (request, ~http as _) =>
  switch Db.find(request.noteId) {
  | Some(_) => Ok(Db.addComment(request.noteId, ~author=request.author, ~text=request.text))
  | None => Error(Errors.NoSuchNote)
  }
)

// src/Server.res: the app mounts the RPCs it serves, by listing their handlers
let rpcs = WeftServer.RpcServer.router([ApiServer.addComment, ApiServer.saveTitle, ApiServer.like])
let app = App.build()->App.router([
  Route.post(list{"_weft", "rpc", ":id"}, async ctx =>
    await rpcs->WeftServer.RpcServer.respond(ctx.request, ~id=ctx->RequestContext.paramOrThrow("id"))
  ),
  ...
])

// in an entrypoint
let addComment = WeftServer.Rpc.use(Api.addComment) // bound to the page's client
switch await addComment(values) {
| Ok(comment) => ...
| Error(Rejected(Errors.EmptyComment)) => ... // from `prepare`: nothing was sent
| Error(Rejected(error)) => ...               // from `check`, or the handler's own `Error`
| Error(Invalid(_)) => ...                    // the server couldn't read the request
| Error(Failed(problem)) => ...               // network, unknown RPC, a handler that threw
}
```

The four type parameters are what the caller passes (`'input`), what goes over the wire
(`'request`), what comes back, and the RPC's own errors. `Rpc.make` has no `~prepare`, and its
`'input` is its `'request`; `Rpc.makePrepared` has one. (As built: one `make` with an optional
`~prepare` can't say that `'input` is `'request` when it's left out, which would let an annotation
claim any input type and send it as the request.) `check` returns `result<unit, 'error>`: it checks,
and doesn't change the request, since it runs on both sides.

**Why two parts, not one definition.** TanStack (like React) defines an RPC in one place, and its
bundler compiles that module twice: for the client, with the handler replaced by a stub that
`fetch`es. ReScript compiles each file once, to one `.res.js` both environments load, so the same
trick here would mean the Vite plugin rewriting ReScript's compiled output to find and remove the
handler (and everything only the handler imports, which sits at the top of the file). That's
pattern-matching compiler output, which is brittle (it's why phase 4's hand-written fixtures were
replaced). Splitting by file reuses the boundary that already exists: the handler's file is
server-only, the plugin keeps it out of the client, and the declaration is safe to ship (an ID,
codecs, and client logic, nothing secret). The ID is the contract between the two halves, and the
types keep them in step: `handler` only accepts a function of the declaration's request, response
and error types.

**Why values, not functors (module functions).** A functor reads well:

```rescript
module AddComment = WeftServer.Rpc.Make({
  let id = "notes.addComment"
  type request = {...}
  type response = Types.comment
  let request = Codec...
  let prepare = ...
})
```

but it doesn't help with the split (a functor whose argument includes the handler puts the handler
in the shared module, so the declaration and the handler are still two functor applications), and
modules aren't values: passing one to a hook (`Rpc.use(AddComment)`) needs a first-class module
(`Rpc.use(module(AddComment))`, and a module type to annotate it with), which is clunkier everywhere
it's used. What a functor does do well, insisting on a complete definition, labelled arguments to
`Rpc.make` do as well: leaving out `~request` is a type error. So an RPC is a value,
`Rpc.t<'input, 'request, 'response, 'error>`, which can be passed around, stored, and given to
hooks.

**`@weft.rpc({id: "..."})`.** On a `let` whose value is `WeftServer.Rpc.make(...)`, `ppx_weft`:

- checks the argument: a record with one field, `id`, a string literal;
- checks the ID's form: dot-separated names, each a letter then letters, digits and `_`
  (`notes.addComment`, `Billing.refund`), so it reads well in a URL and in logs, and nothing like
  `__proto__` or `constructor` is a valid ID;
- passes it to `Rpc.make` as `~id`, and marks the file with a `'use weft rpc <id>'` directive for
  each RPC, which can sit beside an `'use weft entrypoint'` one (a file of entrypoints can declare
  RPCs too; a server file's declarations are pointless, since the client can't import them, and are
  an error). As built, the IDs are in the directives so the plugin reads them from there, rather
  than from the compiled `Rpc.make` calls, whose names and shape are the compiler's;
- fails on everything else: the attribute twice, on something that isn't a `let`, an ID that isn't a
  literal, a declaration in a server file.

The plugin's scan collects every ID from the directives (as it does entrypoint IDs from the marks)
across the app and its ReScript dependencies, and a duplicate fails the build (and the dev server),
naming both files. The router checks again at startup. IDs are explicit, so they're stable across
builds and refactors: renaming a file or moving a declaration doesn't change the endpoint, and an
old client calling a removed ID gets a `Failed` with a 404, which it can answer by reloading.
`Rpc.make(~id)` works without the PPX too (the attribute adds the checks, the scan's duplicate
check, and a place for options later), so the API doesn't depend on it.

**`@@weft.server`**, new in the same phase: a file attribute that makes `ppx_weft` mark a file with
`'use weft server'` even though it has no server components. Today a server-only module without
server components (a database module, an RPC handler) has no directive, so nothing stops client code
importing it but review and the build test's sentinels (§4). With this, the plugin refuses it to the
client the way it refuses a server component's file, naming the chain of imports.

**Calling.** `Rpc.use(rpc, ~base=?)` (a hook, bound to the page's client, from
`Navigation.useNavigation`) returns the function;
`Rpc.call(rpc, ~client, input, ~base=?, ~signal=?)` is the same outside components. A call:

1. runs `prepare` (if any), then `check`: an `Error` there is returned as `Rejected`, and nothing is
   sent;
2. encodes the request with the codec, to JSON;
3. `POST`s it to `<base>/<id>` (`/_weft/rpc` by default) with `content-type: application/json` and
   `x-weft-rpc: 1`;
4. decodes the response (a payload, below) with the page's `Client`, and returns its result.

Network failures, a status other than 2xx, and a handler that threw are `Failed(problem)`:
`{status: option<int>, message: string, digest: option<string>}`, the message a development build's
only, as with `Render`'s errors. Aborting `signal` cancels the request (and, on the server, aborts
the handler's `~signal`). What happens after a mutation is the caller's: use the response,
`Navigation.refresh`, or `refetch` a part of the page.

```rescript
type error<'error> =
  /** `prepare` or `check` said no (on the client: nothing was sent), or the handler returned `Error`. */
  | Rejected('error)
  /** The server couldn't read the request (a client older or newer than it, or a forged request). */
  | Invalid(string)
  /** Anything else: the network, an unknown RPC, a handler that threw. */
  | Failed(problem)
```

**On the server**, `RpcServer.router(handlers)` makes the router, and
`RpcServer.respond(router, request, ~id)` answers the route (as built: a function the route calls,
since `weft_server` doesn't depend on servy). In order, it:

1. looks the ID up in a `Map` made from the handlers (duplicates fail at startup). An unknown ID is
   a 404. Never a property lookup on an object, which is how `"constructor"` or `"__proto__"` turn
   into code;
2. requires `POST`, `content-type: application/json`, the `x-weft-rpc` header, and (by default) an
   `Origin` that's the server's own: 405, 415 or 403 otherwise, before the body is read. A form on
   another site can't send JSON or set the header without the browser asking first (CORS), which is
   the CSRF protection. (As built: the router's `~origins` replaces "the server's own", which is the
   request URL's; a request with no `Origin` isn't a browser's, and is let through unless its
   `Sec-Fetch-Site` says `cross-site`);
3. reads the body up to a size limit (64 KB by default, per router and per RPC): 413 beyond it;
4. parses it with `JSON.parse` (no reviver), then decodes it with the RPC's codec, field by field:
   `Invalid` (a 400) if it doesn't fit, without calling anything else;
5. runs `check`: `Rejected` if it fails;
6. calls the handler with the request and the HTTP `Request.t` (`~http`: headers, cookies, for
   authentication, and its `signal`, which aborts when the client goes away);
7. answers with a payload whose root row is `{"kind": "ok", "value": v}` or
   `{"kind": "error", "error": e}` (a 200; `Invalid` is `{"kind": "invalid", "message": m}`, a 400),
   encoded by `Render` (`Render.valueToStream`, decoded by `Client.valueFromStream`: a response can
   be or contain elements, rendered server components included, and promises that stream in later
   rows), with `cache-control: no-store`. (As built, `kind` rather than an `ok` field: an `ok` of
   `undefined`, a `unit` response, would be left out of the JSON.) A handler that throws gives a 500
   whose root row is an `X` row, through the router's `onError` (a digest, and the message in
   development only).

Every RPC is a public endpoint: anyone can call any ID the router lists, whether the UI does or not,
with any body. Authentication and authorization are the handler's (or a servy middleware's around
the route): an ID is not a secret. The router serves only the handlers it's given, an explicit list
of what's callable, not everything the scan found.

**Serialization, and not repeating React's CVEs.** The two directions are trusted differently, and
get different formats:

- **Responses** (server to client) are the server's own output, so they reuse the payload format
  (`Render` on the server, `Client` on the client) and everything it can carry. The client only ever
  loads entrypoints from the reference map, so a response can't make it load anything else.
- **Requests** (client to server) are anyone's. They must not go through the payload decoder.
  React2Shell (CVE-2025-55182, CVSS 10) was exactly that: React's Flight decoder ran on the server
  against an attacker's request, followed references and property names taken from the payload up
  the prototype chain to the `Function` constructor, and ran code, before any authentication. Our
  payload format has the same kinds of features (row references, `$L` and `$@`, that the decoder
  follows; `$E` entrypoint references that make it load modules; elements it turns into components;
  promises), all of them features that make a decoder _do_ things, which is right for the server's
  own output and wrong for a stranger's.

So a request is plain JSON: what `JSON.stringify` writes and `JSON.parse` reads, with no references,
no tags, and nothing in it that chooses a code path. The server parses it under a size limit and
decodes it with the RPC's codec, which reads only the fields it knows, as own properties, and builds
the request value afresh. A codec is required, not optional. ReScript's types are erased, so a
request cast from parsed JSON to its record type would be whatever the sender sent: a `text: string`
that's an object, or an array of a million items.

The client doesn't encode requests by reflection either (walking the value as `Render` walks props).
That would make ReScript's runtime representations the wire format (variants as `{TAG, _0}`, nested
options boxed by `Primitive_option`), so the server would have to decode exactly those. That ties
the format, and its security, to compiler internals that change between releases. A codec writes an
explicit format, and the same codec reads it on the server.

The rest of the CVEs come out the same way:

- **CVE-2025-55184 and CVE-2025-67779** (denial of service): a self-referencing payload made the
  decoder loop forever. A request has no references to loop on, its size is capped before it's
  parsed, and decoding is linear in its size. `JSON.parse` on absurdly deep nesting throws, which is
  a 400.
- **CVE-2025-55183** (server functions' source code exposed): functions are never serialized
  (`Render` refuses them), handlers live in server-only files the client build can't include, and
  the router answers with nothing but the handler's result.

**Codecs.** Decided: the first of these three ways to get them, with the third as a follow-up.

1. **A small combinator library in `weft_server`** (`Rpc.Codec`): `string`, `int`, `float`, `bool`,
   `option`, `array`, `dict`, `date` (as an ISO string), `object1` to `object8` from fields,
   `variant` from tagged cases, `map` and `custom`. Each value encodes and decodes, so the two can't
   drift. Small, no dependency, easy to fuzz. The one for this phase.
2. **An existing schema library** (`rescript-schema`, also known as Sury): richer (refinements, JSON
   Schema, error paths), but a dependency of every app, and more to ship to the client.
3. **Codecs derived by the PPX** from type declarations (`@weft.codec type addComment = {...}`), as
   `ppx_pretty_print` derives printers: the least boilerplate, exact by construction, and derived
   codecs would just be values of option 1's type. A follow-up, once option 1 has settled.

**Not in this phase:** `GET` RPCs (TanStack's default). Reads already go through pages and server
components, which stream, and a `GET` brings caching, URL limits and side-effect-free rules of its
own. Also left out: `FormData` and files (JSON only; a `Codec.file` over multipart later, under the
same rules); RPCs called without JavaScript (forms posting to an RPC, which needs phase 7's HTML);
and single-flight mutations, where the RPC's response also carries the refreshed page so there's no
second round trip, as Next's server actions can. All of these are possible later.

### 9. Server-rendered HTML and hydration (phase 7)

Planned in full in [`weft_ssr_hydration_plan.md`](weft_ssr_hydration_plan.md), which supersedes this
sketch: the HTML is rendered from the payload decoded on the server, in the `rsc` environment;
entrypoints' hooks run there through `weft_core`'s mount path on fibers in no tree; boundaries
stream as `<template>` segments swapped in by an inline script; and boundaries still pending when
hydration reaches them stay as the server's HTML until their segment arrives. The sketch, as first
written:

Streaming rows without HTML means a blank page until the JavaScript runs. Proper first paint needs
three more things, which are as big as everything above put together, so they come last:

- **An HTML renderer** in `weft_dom` (`WeftDom.Server.renderToStream`): decodes the payload on the
  server (as the browser does), then renders the resulting tree, entrypoints included, to HTML.
  Running entrypoints there means hooks without fibers: `useState` returns its initial value,
  effects don't run, `useContext` reads a context stack the walk keeps, and `use` suspends as in §5.
  `Suspense` boundaries stream: the fallback's HTML goes out with a marker, and the content follows
  later in a hidden element, with a small inline script that swaps it in.
- **Hydration in the reconciler**: `HostConfig.S` gains optional hydration operations
  (`getFirstHydratableChild`, `getNextHydratableSibling`, `canHydrateInstance`, `hydrateInstance`,
  `hydrateTextInstance`), and `beginWork`/`completeWork` adopt existing nodes instead of creating
  them, with a mismatch falling back to client rendering of that boundary.
- **The payload is still sent**, interleaved with the HTML as in §7, because hydrating needs the
  element tree.

### 10. Testing

Every part has tests of its own, and two example apps test the parts together. The tests come in
three tiers, from many fast ones to a few slow ones:

| Tier                 | What runs where                                                                                                                     | Used for                                                              |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| 1. Library           | server and client in one module graph, in one thread; a stub stream between them                                                    | each part's own tests, the in-place update and fuzz tests             |
| 2. App, split realms | server in a worker thread (`rsc` environment), client in jsdom on the test's thread (`client` environment), a `MessagePort` between | most of `weft_notes`' and `weft_split`'s tests, from source and built |
| 3. Browser           | the built app served over real HTTP, driven in Chromium by Playwright                                                               | a handful of smoke tests                                              |

Tiers 1 and 2 are deterministic: the "network" is a stub the test controls (when bytes are
delivered, and in what chunks), and the data the server waits for is behind gates the test opens.
Tier 1 shares everything between server and client, which is harmless for hand-built trees but would
let an app's tests pass for reasons that don't hold in production (shared hook state and module
caches, `document` visible to server code, a client file importing a server one). Tier 2 removes
those differences while keeping the control, and tier 3 is the only one with real HTML streaming,
real `<script>` execution and real chunk loading.

Tests are `*_test.res` with `rescript-vitest`, as elsewhere, except the Vite plugin's and the
browser tests, which are TypeScript.

#### The PPX (`tools/ppx/weft_tests`)

- **Fixtures that compile**: a ReScript package listed in the root `rescript.json` with `ppx_weft`
  in its `ppx-flags`, holding a shared component, a sync and an async server component, a file-level
  and a nested entrypoint, an entrypoint in a module whose name clashes with a JS global (`Error`),
  and a `.res`/`.resi` pair. Its tests check behaviour: `Entrypoint.idOf` gives the expected id for
  each entrypoint, an async server component returns a `Lazy` element that resolves to its body's,
  and a shared one renders as `@jsx.component` would. The compiled `.res.js` files are committed, so
  they're snapshots for free (CI already fails if a build changes them); a test also asserts what
  matters in them: the directive is the first line, and the mark comes after the JSX transform's
  last `make`.
- **Fixtures that don't**: one file per error in §2 (`errors/<Name>.res.in`, so neither the build
  nor the formatter picks them up), each beside the message it should produce (`<Name>.expected`). A
  test compiles each with `bsc -bs-jsx 4 -ppx <the PPX>` from a fresh temporary directory and
  compares the error, with colours and paths stripped, as a Vitest file snapshot (`-u` rewrites
  them). (`bsc -dsource` snapshots of the good fixtures were considered and dropped: it writes
  `.cmi`/`.cmj` files into its working directory and exits non-zero without the build's package
  settings. The committed `.res.js` output shows the same changes.)
- **Compiler canaries** (`canaries/`, compiled the same way but without the PPX): the verified
  points the PPX relies on that can be shown by compiling a file get a fixture each (1, 2 and 5); 3
  is shown by the good fixtures compiling at all, 7 by an assertion on a fixture's compiled output,
  and 4 (the PPX sees the source's path) gets its test in phase 2, when the PPX first uses the path.
  A ReScript upgrade that changes any of them fails a named test rather than something downstream.

#### `weft_core` (`Lazy`, `Entrypoint`, the server-render flag)

On the TestRenderer and TestScheduler, as the existing Suspense tests are:

- a pending lazy suspends to the nearest boundary, and renders when its promise settles; a rejected
  one reaches an `ErrorBoundary`;
- a settled lazy has no fiber of its own: replacing it with the element it resolved to (and the
  other way round) keeps its children's state and host nodes;
- in a transition, a pending lazy keeps the old screen;
- lazies in keyed lists keep their keys' identity when reordered;
- with the server-render flag set, each stateful hook fails with the server message, and `use` still
  throws `Suspended`; and the flag is only set while a server component is being called, so a client
  render that runs in between (possible in a single-process test, and in an app that renders on both
  sides) isn't affected.

#### `weft_server` (tier 1)

- **`Payload`**: every value type in §1 round-trips, including strings starting with `$`, the
  special numbers, nested options, elements and promises; a property test splits encoded rows at
  every position (inside multi-byte UTF-8 characters too) and checks the decoder sees the same rows;
  malformed rows and unknown tags fail clearly.
- **`Render`**, on its own, checking the rows it writes (as text, for small trees): an entrypoint's
  `E` row appears once however often it's used; work outside every boundary is waited for, and under
  a boundary becomes `$L` plus a later row; two boundaries whose data the test resolves in either
  order write their rows in that order, and their work runs concurrently; `Hooks.use` is retried
  after its promise settles; promise props; `onError` sees each error and its digest goes in the `X`
  row (and the message only in development); each development error (a function prop, an event
  handler on a host element, a `ref`, a cycle, a hook) names the component and the path; and
  aborting stops pending work, writes nothing more and calls nothing more.
- **`Client`**, on its own, fed hand-written rows: a row waits for the entrypoints it refers to, and
  each file is loaded once; a load failure, an `X` row and a stream that ends with rows still
  pending each surface as an error at the right element; rows can refer to rows that haven't
  arrived; row 0 being an error rejects `fromStream`.
- **Together**, rendering on the server and decoding into the TestRenderer through
  `WeftServer.Testing`'s stub stream (delivered all at once, a chunk at a time, or re-chunked every
  _n_ bytes) and its map of entrypoints (whose loads can be held), with `navigate` rendering in a
  transition, and the in-place update tests below.
- **In-place updates**, rendering tree A, then refetching and rendering tree B over it. Each
  entrypoint in these tests counts its renders and keeps a counter in state that the test bumps
  before the refetch, and the TestRenderer's operation log shows exactly what changed on the host:
  - _B equal to A_: no host operations at all, every entrypoint's counter kept;
  - _new props_: an entrypoint whose props changed (a string, a nested record, an option, an element
    passed as `children`, a promise) renders again with them and keeps its state; the log has only
    `update`s for the attributes and text that changed;
  - _a different server component, same output_: no remount;
  - _structure_: a keyed list of entrypoints reordered, inserted into and removed from (moves, not
    remounts; removed ones run their cleanups); an entrypoint whose type or key changes remounts and
    its old state is gone; a host element whose tag changes is replaced, with its children
    remounted;
  - _placeholders_: an element that was a `$L` in A and is complete in B, and the other way round,
    keeps its state either way; a refetch whose rows all arrive in one chunk never suspends;
  - _streaming over old content_: while B streams, a boundary already showing A's content keeps
    showing it (not its fallback) until B's content under it is ready, then switches in one commit;
    a boundary new in B shows its fallback; an entrypoint chunk B needs that isn't loaded yet keeps
    A on screen until it is;
  - _ordering_: two refetches of the same place whose responses arrive in the wrong order: only the
    newer is rendered, and the older's stream is cancelled; refetches of two different parts don't
    interfere;
  - _parts refetched_ (`useRefetchable`): a refetch patches only that part's subtree (nothing
    outside it renders, per the render counts) and `isPending` is true until it has; a full
    `refresh()` afterwards with new `children` for the part wins over the refetched content, and a
    refetch after that wins over the `children`; a context provided by an entrypoint above a part
    still reaches entrypoints inside it after a refetch;
  - _errors_: a refetch that fails with an `X` row inside a boundary shows that boundary's error
    while everything else keeps its state; one that fails at row 0 leaves the screen as it was and
    rejects the refetch.
- **Fuzz**, like `weft_core`'s: random trees of server, shared and entrypoint components, then a
  random sequence of mutations (props changed, keyed children moved, inserted, removed, types and
  keys changed, subtrees made async), each rendered on the server and refetched over the last, with
  random delays and random chunking. The oracle is the reconciler itself: after each step the host
  tree must equal rendering the same tree, with the server components already evaluated, directly on
  the client; host node identity must be kept for every node the direct render keeps; and each
  entrypoint's state must be kept exactly where the direct render keeps it. So refetching is checked
  to patch the screen exactly as an ordinary client update would.
- **`Page`**: the shell, rows inlined so that `</script>` in the data can't end the script, the
  bootstrap (in jsdom) picking up rows pushed before and after it loads, and the `Accept` header
  choosing HTML or the bare payload.

#### The Vite plugin (`packages/vite_plugin_weft/tests`)

TypeScript, against small fixture apps (`tests/fixtures`): ReScript packages in the workspace,
compiled through the PPX by the root build like any other, with the output committed. (They were
hand-written `.res.js` files at first, so as not to depend on ReScript; that was brittle, since
nothing kept them like what the compiler writes.) The tests copy a fixture to a temporary directory
and build it, or change its files there as `rescript build -w` would (writing a compiled file again,
taking one away, putting it back), never editing compiled code. `weft_split` below covers a real
app.

- **Unit**: the scan finds exactly the files with the entrypoint directive (in the app, in
  subdirectories and subdirectory lists, and in a ReScript dependency; not in dev sources or files
  without the suffix), with the PPX's ids, and fails on marks that disagree (a compiled file moved)
  or a missing dependency; directives are found only in the prologue, in every compiled fixture file
  as its components call for, and blanked out keeping positions; the generated
  `virtual:weft/client-references` (run, with its `loadModule` refusing other ids) and
  `virtual:weft/assets` (from a hand-made manifest, and in dev).
- **Build**: `buildApp` on a fixture: one chunk per entrypoint file, a shared module in a chunk both
  import, a large client-only module only in its one user's chunk, a sentinel string from a server
  module nowhere in `dist/client`, the export names (`$$Error`) kept, the server's assets made from
  the manifest, the production conditions, and `serve` answering files and pages (and not the
  manifest, or anything outside `dist/client`). A second fixture, whose client code imports a server
  file through a shared one, fails to build with the chain in the message; so does the first without
  the PPX in its `rescript.json`.
- **Dev**: `createServer` in the test process: a page and a payload come back through the
  middleware, with the development conditions; the client gets the references and directive-free
  files, and is refused a server file (with the chain) and the server's virtual module; changing a
  server-only file sends the refresh event on the client's HMR channel and the next request runs it
  again, changing an entrypoint file sends a full reload, and an entrypoint file appearing (or being
  deleted) updates the references.

#### Tier 2: the app harness (`@e-cline/vite_plugin_weft/testing`)

The harness for testing an application, which apps outside this repository can use too. It's
TypeScript, since it's Vite and worker plumbing, and ships ReScript bindings (`WeftTesting`, a
module in the plugin package, as `ppx_pretty_print` ships `PrettyPrint`), so the examples' tests
stay in ReScript.

```
 Vitest worker (jsdom)                                  worker_thread (no DOM)
 ─────────────────────                                  ──────────────────────
 the test                                               Vite module runner for the "rsc"
   │                                                    environment, fed by the harness's
   ▼                                                    in-process Vite server (middleware mode)
 client: WeftDom root, WeftServer.Decoder,                 │
   entrypoints from the real                              ▼
   virtual:weft/client-references                       the app's fetch handler
   (the plugin's client environment                     the fake database and its gates
   applied to the test's own graph)                       ▲
   │                                                      │
   └── fetch ──> MessagePort: request, then response ─────┘
                 bytes, delivered as the test says;
                 cancellation; calls into the server
```

One harness (a Vite server and a worker) is made per test file and reset between tests; each test
opens pages on it:

```rescript
let app = await WeftTesting.start(~root=packageRoot) // or ~mode=Build, ~buildDir
let page = app->WeftTesting.open_(~container, ~delivery=Manual, "/notes/1")
page->WeftTesting.deliver->ignore                  // hand the client the next chunk
await page->WeftTesting.waitFor(() => page->WeftTesting.has("#title"))
await page->WeftTesting.settle                     // deliver everything, until it's quiet
let _ = await app->WeftTesting.callServer("tests/FakeDbControl.res.js", "release", [JSON.String("comments:1")])
await page->WeftTesting.navigate("/notes/2")       // through the page's own navigation
```

As built: the server side is TypeScript (`src/testing.ts`, and `src/testingWorker.ts`, the worker),
and so is the page's DOM work, while `WeftTesting.res` passes in what only the test's module graph
can import (the bootstrap, the reference map, `WeftDom.Client.act`). The rsc environment is a
`DevEnvironment` whose hot channel posts to the worker, and the worker's `ModuleRunner` invokes
`fetchModule` back over the port (`hot.handleInvoke`). A test file starts one app (`beforeAll`), and
each test opens pages on it, in containers of its own.

- **Two realms.** The server code runs in the worker with its own module instances (its own
  `HookImpl`, `Env` and entrypoint marks), its own globals and no DOM: server code touching
  `document` fails as it would in production. The client runs in Vitest's jsdom environment with the
  weft plugin applied as the client environment, so `virtual:weft/client-references` is the real
  one, and a test whose client code imports a server file fails the way the browser build would.
- **Transport.** The client's `fetch` posts the request (method, URL, headers, body) over the port;
  the worker calls the app's handler and sends back the status, headers and body bytes. The harness
  hands those to the client everything at once, one chunk per `deliver`, or re-chunked every _n_
  bytes, so a scenario can be run at several chunk sizes. Cancelling the response on the client (a
  navigation away) cancels the body stream in the worker, so the server sees the abort. Requests
  from `navigate`, `refresh`, refetches and entrypoints' own `fetch`es (a form posting a comment)
  all go this way.
- **Calling into the server.** `callServer(module, export, args)` imports a module through the
  worker's runner (the same instance the app uses) and calls an export with JSON arguments. It's how
  tests open the fake database's gates, ask which queries are waiting, or change data behind the
  app's back ("another user added a comment"). Test-only control modules live in the app's `tests/`,
  so the app itself has no test hooks.
- **The first page**: the HTML response is read as the bootstrap would, rows taken from the inline
  scripts and the rest checked to be the shell, so the HTML path is covered without a browser.
- **Entrypoints** load through the real reference map; `page->WeftTesting.holdLoads` holds them, to
  test a slow chunk.
- **Rendering** goes through `WeftDom.Client.act`. A page streams for as long as the server has
  something to send, so "everything has arrived" isn't something to wait for: `waitFor(predicate)`
  waits for what the test expects, and `settle` until nothing has changed for a while.
- **Checking an update was in place**: `page->WeftTesting.snapshot` records the DOM nodes under the
  container, and `removedSince(page, snapshot)` lists those no longer there (expected to be `[]`);
  `renderCount(page, id)` counts an entrypoint's renders (the harness wraps each loaded `make`, the
  same wrapper every time); `pageRequests` lists the page's requests.
- **`Build` mode** runs the build: the worker imports its `server/index.js`, and the page is the
  built client's own bootstrap and chunks (with their own copy of Weft, which is why the harness
  can't hand the page a bootstrap of its own then). Since those modules are shared, a build-mode
  test file opens one page and moves on by following links; `loads`, `holdLoads` and `renderCount`
  are source-mode only.

**Proving it out first.** This leans on less-trodden Vite APIs: a module runner in a worker with a
custom transport, and Vitest applying a plugin's client environment to the test's own graph. Phase 5
started with a spike of the transport against the plugin's `basic` fixture
(`packages/vite_plugin_weft/tests/harness.test.ts`): the worker approach worked first time (the
server has no `document` or `window`, runs with the development conditions, and runs changed code
once Vite sees the change), so the one-thread fallback wasn't needed.

#### Weft RPCs (phase 6)

- **Codecs**: every combinator round-trips (property tests over random values); decoding rejects
  wrong types, missing fields and values out of range, with the path to what's wrong; extra fields
  are ignored; `__proto__`, `constructor` and `prototype` keys in a request are inert (decoded
  records are built afresh, and no prototype changes).
- **The router**, against hand-made requests: unknown IDs (`__proto__`, `constructor`, `toString`
  and `hasOwnProperty` among them) are 404s; a wrong method, content type or `Origin`, or no
  `x-weft-rpc` header, is refused before the body is read; an oversized body, malformed JSON and
  very deep nesting are 4xx without the codec or handler running; a request the codec rejects is
  `Invalid`, one `check` rejects is `Rejected`, and in neither case is the handler called; a
  handler's `Error` is `Rejected`, its `Ok` the response, and a throw `Failed` (with the message in
  development only); duplicate IDs fail when the router is made.
- **A fuzz test**: random bytes and random JSON sent to every route of a router with a few RPCs: the
  server never crashes, never answers 5xx for a bad request, and no handler is ever called with a
  request its codec wouldn't produce.
- **Calls**, from the client through an in-process server (as `Support.serve` does for pages):
  `prepare` refusing sends nothing; aborting cancels the handler; responses with elements (a server
  component's output) and with promises stream in; a 404 or a network failure is `Failed`.
- **The PPX**: fixtures that compile (the ID passed as `~id`, the directive written beside an
  entrypoint one, `@@weft.server` writing `'use weft server'`) and errors (no literal, a bad ID, the
  attribute twice or on something other than a `let`, a declaration in a server file).
- **The plugin**: the scan finds RPC IDs in the app and its dependencies; a duplicate fails the
  build and the dev server, naming both files; an `@@weft.server` file is refused to the client,
  naming the chain.
- **`weft_notes`** (tier 2): saving a title, adding a comment and liking go through RPCs; a comment
  `prepare` refuses shows its error with no request made (`pageRequests`); one the handler rejects
  shows that error; a request the server can't read (an older client, simulated by a codec that
  doesn't match) is `Invalid`, and the page says so. One browser test posts a comment through an
  RPC. As built, the older client is played by the harness's `rewriteBodies`, which changes the
  request on its way to the server; it also plays a client that skipped `check`, which the server's
  own `check` refuses.

#### Example apps

Both are Vite apps served by `@e-cline/servy`, with their data behind an interface the tests
replace: a fake database, in the server's realm, whose queries each wait on a named gate the test
opens through `callServer`, so the order things finish in is the test's choice, not a timer's. In
`vp dev` the gates are timers instead, so the streaming is visible by hand; in the browser tests, a
test-only route opens them.

**`examples/weft_notes`**: the integration test bed, using every feature in a small notes app: a
list page and a note page with three boundaries (the note, its comments, related notes), a
`LikeButton` entrypoint with state, a comment form entrypoint that posts to a route and calls
`refresh()`, a `CommentList` entrypoint receiving its comments as a promise prop, a `NoteEditor`
entrypoint (a draft in state, the saved title and "saved at" time as children rendered on the
server) whose save posts and refetches those, the comments in a `CommentsPanel` entrypoint that
refetches them with a reload button, a server component that fails inside an error boundary, and
links that `navigate`. Its tests, through the tier 2 harness, from source:

- the shell and row 0 render, then each boundary's content replaces its fallback as its gate opens,
  in whichever order the test opens them;
- the same final DOM at chunk sizes 1, 7 and 4096, and with everything delivered at once;
- a like count survives navigating between two notes and a `refresh()`;
- posting a comment, then `refresh()`, shows it, with the form's other state kept;
- the promise prop shows `CommentList`'s own fallback until its gate opens;
- the failing component shows the boundary's error, and the rest of the page renders;
- with `LikeButton`'s chunk held, the rest of the page renders, and the button appears once it
  loads;
- navigating away while the page is still streaming cancels the old response (the fake database sees
  its waiters abandoned) and none of its rows land;
- saving in `NoteEditor` refetches the saved title: the new title and "saved at" arrive, the draft
  and the input's focus and selection are kept, the input is the same DOM node, and nothing outside
  the refetched part changes (`removedSince`, render counts);
- reloading the comments after another "user" adds a comment through the fake database: the new
  comment is inserted, the existing comment nodes are kept, and a comment whose text was edited is
  updated in place;
- the like count changes on the server while `LikeButton` has a local "just liked" state: after a
  `refresh()` the button shows the server's count and keeps that state;
- reloading comments while their gate is held keeps the old comments on screen (not the fallback),
  with `isPending` true, until the gate opens;
- reloading comments twice, with the first response held until the second has rendered: the first
  never lands.

**`examples/weft_split`**: code-splitting, with the real ReScript and PPX output the plugin's
fixtures stand in for: file-level and nested entrypoints, one in a module named `Error`, two
entrypoints sharing a module, an entrypoint that renders another, one used on only one route, a
large client-only module (with a sentinel) imported by one entrypoint, and a server-only module
(with another). Its tests:

- **the build** (phase 4): the app built with its own config, then assertions on the manifest and
  `dist/client`: each entrypoint file is its own chunk, the shared module is a chunk both import,
  the entrypoint rendering another imports its chunk, the large module is only in the chunk of the
  entrypoint using it, the server sentinel and the directives are nowhere, and `$$Error` is
  exported; then the built server's payload for each route, decoded with the built chunks, loads
  exactly the entrypoint files that route uses;
- **the built app, through the harness** (`Build` mode): every route renders, and only the chunks a
  page uses are loaded;
- the same scenarios in `Source` mode, so a difference between dev and build shows up as one passing
  and the other failing.

#### Tier 3: browser smoke tests (`examples/weft_notes/e2e`)

A few Playwright tests (`@playwright/test`, Chromium only) against `weft_notes` built and served
over real HTTP (port 4317, or `WEFT_NOTES_E2E_PORT`), with test-only routes to open the gates,
enabled by `WEFT_NOTES_TEST_ROUTES=1`, which the test server sets:

- the first page streams: the shell and row 0 show, then each boundary fills in as its gate opens;
- an entrypoint's chunk is requested only once a page uses it, and once only (from the network log);
- saving in `NoteEditor` refetches the saved title and keeps the input's focus and selection;
- navigating between notes keeps the like button's state, and the back button works.

They run in CI on one Node version, as a job of their own (`vp run e2e`, after
`playwright install --with-deps chromium`), since they need a browser installed. (The job was
written in phase 5 but hasn't run in CI yet: it'll first run on the PR.) They're few by design:
anything that can be checked in tier 2 is, and these cover what only a browser can show. Phase 7
adds hydration's (no flash of client rendering, the server's nodes kept).

## Packages and layout

```
tools/ppx/setup.sh, rescript_ppx.opam.locked   the shared OCaml toolchain (moved from pretty_print)
tools/ppx/weft/                    @e-cline/ppx_weft: ppx_src/ppx_weft.ml, bin/main.ml, ppx script
packages/weft/src/Weft.res(i)      gains a `Lazy` alias (useful in client-only apps too)
packages/weft_core/src/
  Lazy.res(i)                      `Lazy.fromPromise`; Element.kind gains `Lazy`
  Entrypoint.res(i)                `mark` (what the PPX calls) and `idOf`, for renderers
  ServerRender.res(i)              `run`: call a component as a server render (the hooks flag)
packages/weft_server/              namespace WeftServer (by where it runs, since phase 7.0)
  src/shared/Payload.res(i)        the row and value encoding, shared by both ends
  src/server/Render.res(i)         server renderer: element => ReadableStream
  src/shared/Decoder.res(i)        stream => elements; fetchElement, Latest (was `Client`)
  src/server/Page.res(i)           the HTML shell with inlined rows; respond (HTML or payload)
  src/client/Bootstrap.res(i)      the browser's start: rows from the page, a root, history
  src/shared/Navigation.res(i)     the page: navigate, refresh, useNavigation, useRefetchable
  src/shared/Rpc.res(i)            Weft RPCs (phase 6): make, makePrepared, call, use
  src/server/RpcServer.res(i)      handler, router, respond (split from `Rpc` in phase 7.0)
  src/shared/RpcCodec.res(i)       their codecs, as Rpc.Codec
  src/testing/Testing.res(i)       tier 1 helpers: a stub stream, entrypoints served from a map
packages/vite_plugin_weft/         @e-cline/vite_plugin_weft (TypeScript)
  src/testing.ts, testingWorker.ts the tier 2 harness (`/testing` export): Vite server, worker, port
  src/WeftTesting.res(i)           its ReScript bindings
  tests/fixtures/                  small ReScript apps, compiled by the root build
tools/ppx/weft_tests/              fixtures that compile, fixtures that don't, compiler canaries
examples/weft_notes/               notes app: the integration test bed (§10)
  tests/                           tier 2 scenarios, and the fake database's control module
  e2e/                             tier 3 Playwright tests
examples/weft_split/               code-splitting edge cases, tested built and from source (§10)
```

Each package gets the usual wiring: root `rescript.json` `dependencies` and a `workspace:*` root
`devDependency` for the ReScript ones, a README row, error codes in its README, and a changeset.

## Phases

Each ends green (`pnpm run build`, `pnpm run test`, `pnpm run check`) and is its own commit (or a
few). For now they all go in one PR, `claude/weft-ppx-phase-0`, rather than a PR each.

**Phase 0 -- Pin what the compiler does.** A `ppx_weft` that replaces `@weft.component` with
`@jsx.component` (every kind compiling as a shared component for now), and already checks the
attribute: its argument, where it is, and that a binding has it once and not with `@jsx.component`.
The PPX test package with the first good fixtures, those errors and the compiler canaries (§10), and
the opam setup moved to the shared switch.

**Phase 1 -- `WeftCore.Lazy` and `Entrypoint`.** The new element kind, unwrapped in
`ChildReconciler`; `Entrypoint.mark`; the server-render flag in `HookImpl`, set through a public
`ServerRender.run` (since `weft_server` is another package), with `Hooks.use` allowed under it;
error codes 13 (an unresolved lazy reaching the reconciler) and 14 (a stateful hook on the server);
the `Weft.Lazy` alias; with their tests (§10).

**Phase 2 -- The PPX in full.** Async rewriting, marks, ids, directives and the rest of the errors
in §2 (`async` outside a server component, server components and entrypoints in one file,
function-typed props, an entrypoint not named `make`, no `rescript.json` to name it by), with the
rest of the PPX's fixtures, good and bad, and canary 4 (§10): the ids are made from the source path
the PPX is given, so the tests of the ids are that canary.

**Phase 3 -- Wire format and renderer, no bundler.** `Payload`, `Render` and `Client`, each tested
on its own and then together into the TestRenderer, including every in-place update test and the
update fuzz test (§10), with `fetchElement` and request ordering (`Client.Latest`).
`WeftServer.Testing` (the tier 1 helpers: a pipe the test controls, modules from a map) comes with
them. `weft_core` gains `Deferred` (rows readable the moment they arrive),
`ServerRender.suspendedOn` (so the renderer needn't reach into its internals), and rejected lazies
throwing from their own position. Refetching part of a page (§7) waits for phase 5, with pages and
navigation; those cases of the in-place tests come with them.

**Phase 4 -- The Vite plugin, and `weft_split`.** Environments, the virtual modules, the scan, the
boundary check, the dev middleware and the build, with the plugin's unit, build and dev tests on its
fixtures. Then `examples/weft_split` and its build tests, the first time the real PPX output goes
through the plugin. (Its harness tests wait for phase 5.) Done; it also brought `serve` (running a
build on Node), the missing-PPX check, and server HMR as far as the plugin goes (the event, and
`onRefresh`). Until `Page` exists, `weft_split`'s server answers a page with a shell that loads the
bootstrap, which then fetches the payload; it works the same in `vp dev` and built.

**Phase 5 -- Pages, navigation, the harness and `weft_notes`.** First the tier 2 spike (§10), which
decides between the worker and the one-thread fallback. Then `Page`, the bootstrap,
`navigate`/`refresh`, refetching part of a page, and server HMR; the tier 2 harness and its
bindings; `examples/weft_notes` with its scenario tests; `weft_split`'s harness tests, from source
and built; and the tier 3 browser tests, with the `e2e` task wired into CI. Done. Along the way:
navigation became a module of its own (`Navigation`, with `useRefetchable`, which replaced `Frame`
after review), `Bootstrap` and the plugin's default bootstrap came with it, `weft_server` gained
dependencies on `weft_dom` (the bootstrap) and `@rescript/webapi` (`Page.respond`), cancelled
payloads leave their rows waiting rather than failing them, the server took over warning about
missing keys, and `weft_split` switched to `Page` and the default bootstrap (with a `Link`
entrypoint, for navigating in build mode).

**Phase 6 -- Weft RPCs** (§8), as decided (Decisions): `WeftServer.Rpc` (`make`, `handler`,
`router`, `call`, `use`) and its codecs; `@weft.rpc` and `@@weft.server` in `ppx_weft`, with their
fixtures and errors; the plugin's scan collecting RPC IDs (duplicates fail the build); then
`weft_notes`' posts (saving a title, adding a comment, liking) moved to RPCs, with the tests in §10.
Done. Along the way (§8 says where): `Rpc.make` and `Rpc.makePrepared` (with `~prepare`) rather than
one `make`; `check` returning `result<unit, 'error>`; one `'use weft rpc <id>'` directive per RPC,
which the scan reads the IDs from; `RpcServer.respond(router, request, ~id)` for the route;
`Render.valueToStream` and `Client.valueFromStream`, for payloads whose root isn't an element; error
codes 18 (a bad ID) and 19 (an ID twice in a router); the harness's `rewriteBodies`, to play an
older client; and in `weft_notes`, `ApiServer` for the handlers, with it, `Db`, `Gates` and `Server`
marked `@@weft.server`.

**Phase 7 -- HTML and hydration** (§9): the hook-less HTML renderer, streaming Suspense HTML, then
hydration in the reconciler and the DOM host. Now its own plan,
[`weft_ssr_hydration_plan.md`](weft_ssr_hydration_plan.md), in six phases (7.1 to 7.6). The harness
carries over: the first page's HTML is put into the container before the client starts, and
`weft_notes`' scenarios are run again checking that hydration reused the server's nodes; the browser
tests check the same in Chromium.

Out of scope: the Flight wire format and interop with React, CSS handling beyond what Vite does
already, shared references and cycles in payloads, context on the server, and caching rendered
output.

## Decisions

Settled before phase 0, since these names and this setup get built into everything after:

- **The kind is `Entrypoint`**, not `Client`: the PPX parses the word and every entrypoint file
  contains it. "Entrypoint" says more precisely what it is: where client code starts, with
  everything it imports coming along.
- **The package is `weft_server`** (namespace `WeftServer`), not `weft_rsc`. It can't be confused
  with the HTTP framework, which is Servy.
- **The two PPXs share one opam switch**, `rescript_ppx`, set up by `tools/ppx/setup.sh` from one
  lock file (see §2's "Toolchain"), rather than each having its own and compiling OCaml twice.

Settled before phase 6 (Weft RPCs, §8), as §8 recommended:

- **An RPC's declaration and handler are in two files** (shared and server-only), joined by the ID
  and the types, rather than one definition the plugin splits by rewriting compiled output.
- **An RPC is a value** made with labelled arguments (`Rpc.make`), not a functor.
- **Codecs are `weft_server`'s own** small combinator library (`Rpc.Codec`); PPX-derived codecs may
  follow.
- **Errors**: `Rejected('error)` for the RPC's own errors, from `prepare`, `check` and the handler
  alike (one type, so a form shows them the same way); `Invalid` for a request the server couldn't
  read; `Failed` for everything else. The promise never rejects.
- **The app mounts its RPCs** by listing their handlers in `RpcServer.router`, on a route of its
  own: the list is what's callable. The plugin's scan only checks IDs for duplicates.
- **`POST` and JSON only** for now; `GET` RPCs and `FormData` later.
- **IDs are dot-separated names**, checked by the PPX; the default path is `/_weft/rpc/<id>`.
- **`@@weft.server` comes in this phase**, for handler files and any other server-only module.
- **Authentication is servy middleware** around the RPC route (handlers get the HTTP request); the
  router has no middleware of its own.
- **Responses can be or contain elements and promises**, through the payload format.

## Risks

- **An RPC is a public endpoint**, which is easy to forget when calling one looks like calling a
  function. The docs say so first; the router serves only what it's given, and the example's
  handlers check what they need to.
- **Codecs are boilerplate**, and boilerplate drifts or gets skipped. A required codec can't be
  skipped (`Rpc.make` doesn't compile without one), and PPX-derived codecs would remove most of it.
- **The PPX depends on compiler details**: that external PPXs run before the JSX transform, and the
  AST encoding ppxlib 0.34 reads. Phase 0's tests exist to catch a ReScript upgrade changing any of
  these.
- **A missing PPX fails loudly, but unclearly.** Without `ppx_weft` in `ppx-flags`,
  `@weft.component` is ignored and every use of the component is a type error about `component<'a>`
  (verified point 2), which doesn't say what's wrong. Nothing builds, so it can't ship; the README
  should lead with the setup, and list that error as its symptom.
- **Async server components only work in the server renderer.** It calls one once and waits;
  rendering one with the client reconciler would call it on every render, each time with a new
  promise, and never settle (found writing phase 2's tests: the loop runs in microtasks, so it even
  starves a test runner's timeout). In an app, the Vite plugin keeps server files out of the client;
  in tests, async server components go through the server renderer (or are called once and awaited).
- **Hooks on the server.** Shared components that call `useState` work in the browser and fail on
  the server, which is only found at runtime. React has the same limitation; the error message is
  the mitigation.
- **Serializability isn't typed.** Props are checked at runtime (and function types syntactically by
  the PPX). A typed alternative, deriving codecs for props as `ppx_pretty_print` derives printers,
  would catch more at compile time but force every prop type to be annotated; not worth it for now.
- **The directory scan includes unreachable entrypoints.** Harmless chunks, and simpler than
  building the server graph first. Revisit if apps get large.
- **Entrypoints render again on every refetch.** Decoded props are new objects each time, so even an
  entrypoint whose props didn't change renders again (its host output is still diffed, so the screen
  doesn't change). The decoder could reuse the previous payload's values where they're structurally
  equal, so `Memo` bails out; that's an optimisation for later, and the render-count assertions
  above pin down today's behaviour.
- **The tier 2 harness depends on young Vite APIs** (a module runner in a worker, and a plugin's
  client environment inside Vitest), which could change. The phase 5 spike showed they work today;
  the harness's own tests (`tests/harness.test.ts`) would show it if they stop.
- **jsdom isn't a browser**: focus follows clicks in one and not the other, for one. The browser
  tests cover what the scenarios found jsdom getting differently.
- **Tiers 1 and 2 never run real HTML streaming or chunk loading.** The browser tests do, but only
  for a few scenarios, so a browser-only problem elsewhere could get through. Keeping the first
  page's HTML reading in tier 2 identical to the bootstrap's (one shared module) narrows it.
