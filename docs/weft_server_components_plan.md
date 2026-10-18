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
 WeftServer.Render.toStream(<NotePage id />)         WeftServer.Client.fromStream(rows)
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
  renderer have no fiber; `HookImpl` gets a "rendering on the server" flag so `useState`, effects,
  `useContext` and the rest fail with a message saying so (rather than "called outside a
  component"). `Hooks.use(promise)` works: it suspends the component, which the server renderer
  retries once the promise settles (§5).
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
needs OCaml < 5.4), so rather than a second opam switch that compiles OCaml again, move `setup.sh`
and the lock file up to `tools/ppx/`, rename the switch to something shared (`rescript_ppx`), and
have both packages' `build` tasks use it. That also means updating `.vscode/settings.json`'s
`ocaml.sandbox`, the CI opam cache key, and the root `res` task's `dependsOn`, which gains
`@e-cline/ppx_weft#build`.

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
written every `.res.js` before Vite starts, so a glob over the app's sources (and its ReScript
dependencies') is simple and deterministic, and doesn't need a server build first. The cost is that
an entrypoint no server component renders still gets a chunk, which is harmless. (React's plugin
instead builds the server graph first to find client references; that can come later if it's ever
needed.)

One thing to test early: ReScript renames modules that clash with JavaScript globals in its output
(a module `Error` is exported as `$$Error`). The client has to walk the same names; the simplest fix
is for the PPX to write the JS export path into the id, applying the same rule.

### 4. The Vite plugin (`packages/vite_plugin_weft`, `@e-cline/vite_plugin_weft`)

TypeScript, on the Environment API. Configured with the server entry (a module exporting a fetch
handler, as `@e-cline/server`'s `App.t` is) and the client bootstrap's options:

```ts
// examples/weft_notes/vite.config.ts
plugins: [weft({server: './src/Server.res.js'})],
```

What it does:

- **Two environments**: `rsc` (Node; runs server components) and `client` (browser). React's plugin
  needs a third, `ssr`, because React has a separate build for server components (the `react-server`
  condition); Weft's runtime is the same everywhere, so HTML rendering (phase 6) runs in `rsc` too.
- **Virtual modules**:
  - `virtual:weft/client-references` (client): the map in §3.
  - `virtual:weft/client` (client): the bootstrap. Reads the rows the HTML stream delivers, creates
    a `WeftDom.Client` root and renders into it, and wires up navigation (§7).
  - `virtual:weft/assets` (rsc): the bootstrap script's URL, and, for each entrypoint file, its
    chunk and the chunks it imports (for `modulepreload` hints). In dev these are `/src/...` URLs;
    in a build, they come from the client build's `manifest.json`.
- **Enforcing the boundary.** In the client environment's `transform`, a module with the
  `'use weft server'` directive is an error, naming who imported it. Both directives are removed in
  `transform` (bundlers warn about module-level directives they don't understand).
- **Dev server.** A middleware passes requests to the server entry through the `rsc` environment's
  module runner (`@hono/node-server`'s `getRequestListener` turns the fetch handler into a Node
  listener), so a request always runs the current code. ReScript compiles in its own process
  (`vp run -w res:watch`), so changes arrive as `.res.js` writes:
  - a server-only module changed: send a custom HMR event, and the bootstrap refetches the current
    page's payload and renders it in a transition, keeping client state, like React's server HMR;
  - a client module changed: a full reload (Weft has no fast refresh).
- **Build** (`buildApp`): the client first (its entries are the bootstrap and every entrypoint file,
  known from the scan), then `rsc`, whose `virtual:weft/assets` reads the client manifest. Output:
  `dist/client/` (static files) and `dist/server/index.js` (the handler). The example's `start` task
  serves both.
- **Conditions.** `@e-cline/js_env`'s development/production export conditions (which
  `Common.Env.isDev` relies on) have to be set for the `rsc` environment as well as the client.

### 5. The wire format and the server renderer (`packages/weft_server`)

A new ReScript package, namespace `WeftServer`, depending on `weft_core` and nothing
server-specific: `Render` produces a Web `ReadableStream<Uint8Array>`, which `@e-cline/server`'s
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

- Server and shared components are called with their props, and their result walked.
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
  sees every one and returns the digest, as React's does. `signal` aborting (the client went away;
  `ByteStream` already reports that as `Cancelled`) stops everything pending.

### 6. The client decoder, and `WeftCore.Lazy`

`WeftServer.Client.fromStream(stream, ~loadEntrypoint) : promise<Element.t>` resolves with row 0's
element once it's decodable, and keeps decoding as rows arrive. `loadEntrypoint` (an id to a promise
of the module) is what the bootstrap fills in from `virtual:weft/client-references`; taking it as an
argument, like `navigate`'s `fetch` below, is also what lets tests run without Vite (§9).

- Each row is a promise, created when the row is first referred to or first arrives, and marked with
  `weft_core`'s `$$fiberStatus` when it settles, so `Hooks.use` can read it synchronously.
- An `E` row starts its `import()` immediately. A `J` row that refers to an entrypoint isn't turned
  into elements until that module has loaded (Flight's "blocked" chunks), so an entrypoint element's
  type is always the component's real `make`, never a loader wrapper. That matters for refetching:
  the same entrypoint in the same place in the next payload is the same type, so the reconciler
  keeps its state.
- `"$L5"` becomes a `WeftCore.Lazy` element around row 5's promise. `"$@5"` becomes the promise
  itself. `"$S"` becomes a `WeftCore.Suspense` element; host types become `JsxCore.hostJsx`
  elements.

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

### 7. Pages, streaming, navigation and refetching

**The first request** (before phase 6's HTML rendering) gets one streamed HTML response: the
document shell, `<div id="root">`, the bootstrap `<script type="module">` and `modulepreload` links,
then the payload's rows as they're produced, each as an inline `<script>__weft.push("...")</script>`
(escaped with `Html.json`'s rules), until the payload ends. The bootstrap drains `__weft` and
listens for more, so rows that arrive before or after it loads are both handled, and there's one
request, not a page then a fetch. The page shows nothing until the bootstrap and row 0 are in, but
everything under a `Suspense` boundary streams in after that.

**Navigation** fetches the same route with `Accept: text/x-weft-payload`, which the server answers
with the bare payload, and renders the result into the root inside `Transition.start`: the old
screen stays until the new tree can render (Suspense phase c), entrypoints in the same place keep
their state, and the reconciler only touches what changed. `WeftServer.Client.navigate(url)` and
`refresh()` are the API; a router (link interception, history) is the example's job, kept small.
Both use a `fetch` the client is created with (the global one, from the bootstrap), so a test can
give it one that goes to a stubbed server instead (§9).

A helper in `weft_server` (or the example) puts this together for `@e-cline/server`:
`Page.respond(request, element)` picks HTML or payload from the `Accept` header.

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
its stream cancelled.

**Refetching part of the page.** A whole-page `refresh()` is the simple case. For a part of it,
`WeftServer.Frame` is a built-in entrypoint (part of `weft_server`'s client modules, always in the
plugin's reference map, and marked with `Entrypoint.mark` by hand, since `weft_server` itself
doesn't use the PPX) that a server component wraps around a subtree:

```rescript
// in a server component
<WeftServer.Frame name="comments" src={`/notes/${id}/comments`}>
  <Comments noteId=id />
</WeftServer.Frame>

// in any entrypoint below it, or elsewhere on the page
let comments = WeftServer.Client.useFrame("comments")
<button onClick={_ => comments.refetch()}> {Weft.Jsx.string("Reload")} </button>
// comments.isPending is true until the new subtree has rendered
```

The frame renders its `children` (rendered on the server, like any element prop) until it's
refetched, then fetches `src` (or a URL `refetch` is given) as a payload, and renders that element
in their place, in a transition, under the same rules. The route at `src` renders just that subtree,
with `Page.respond`. If a later full `refresh()` or `navigate` gives the frame new `children`, the
newest content wins, whichever way it came. Underneath is `WeftServer.Client.fetchElement(url)`, a
promise of a decoded element an entrypoint can keep in its own state, for anything `Frame` doesn't
cover.

### 8. Server-rendered HTML and hydration (phase 6)

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

### 9. Testing

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

#### The PPX (`tools/ppx/weft/tests`)

- **Fixtures that compile**: a ReScript package listed in the root `rescript.json` with `ppx_weft`
  in its `ppx-flags`, holding a shared component, a sync and an async server component, a file-level
  and a nested entrypoint, an entrypoint in a module whose name clashes with a JS global (`Error`),
  and a `.res`/`.resi` pair. Its tests check behaviour: `Entrypoint.idOf` gives the expected id for
  each entrypoint, an async server component returns a `Lazy` element that resolves to its body's,
  and a shared one renders as `@jsx.component` would. The compiled `.res.js` files are committed, so
  they're snapshots for free (CI already fails if a build changes them); a test also asserts what
  matters in them: the directive is the first line, and the mark comes after the JSX transform's
  last `make`.
- **Fixtures that don't**: one file per error in §2 (`tests/errors/*.res`), each beside the message
  it should produce. A Node test runs `bsc -bs-jsx 4 -ppx <the PPX>` on each and compares the error,
  with colours and paths stripped. `bsc -dsource` on the good fixtures, checked in as `.expected`
  files, shows the source after the PPX and the JSX transform have both run, which makes a change in
  the PPX's output easy to review.
- **Compiler canaries**: the verified points that the PPX relies on (1--5 and 7) get a fixture each,
  so a ReScript upgrade that changes them fails a named test rather than something downstream.

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
    newer is rendered, and the older's stream is cancelled; refetches of two different frames don't
    interfere;
  - _frames_: `useFrame(name).refetch()` patches only that frame's subtree (nothing outside it
    renders, per the render counts) and `isPending` is true until it has; a full `refresh()`
    afterwards with new `children` for the frame wins over the refetched content, and a refetch
    after that wins over the `children`; a context provided by an entrypoint above a frame still
    reaches entrypoints inside it after a refetch;
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

TypeScript, against small fixture apps whose "compiled ReScript" is hand-written `.res.js` files
(directives included), so these tests depend on neither ReScript nor the PPX; `weft_split` below
covers the real thing.

- **Unit**: the scan finds exactly the files with the entrypoint directive; directives are removed;
  the generated `virtual:weft/client-references` and `virtual:weft/assets`; a client import of a
  server file fails, naming the chain.
- **Build**: Vite's `build` on a fixture: one chunk per entrypoint file, a sentinel string from a
  server module appears nowhere in `dist/client`, and the manifest names each entrypoint's chunk and
  its imports. A second fixture, whose client code imports a server file, fails to build with the
  expected message.
- **Dev**: `createServer` in the test process: a page and a payload come back through the
  middleware; changing a server-only file sends the refresh event on the client's HMR channel, and
  changing an entrypoint file a full reload.

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
 client: WeftDom root, WeftServer.Client,                 │
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
let app = await WeftTesting.start(~root=packageRoot, ~mode=Source) // or Build("dist")
let page = await app->WeftTesting.open_(~container, ~delivery=Manual, "/notes/1")
page->WeftTesting.deliver                          // hand the client the next chunk
await page->WeftTesting.settle                     // deliver everything, finish loads and renders
await app->WeftTesting.callServer("tests/FakeDbControl.res.js", "release", ["comments:1"])
await page->WeftTesting.navigate("/notes/2")       // through the client's own navigate
await page->WeftTesting.refetchFrame("comments")   // as useFrame(name).refetch() would
```

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
  from `navigate`, `refresh`, frames and entrypoints' own `fetch`es (a form posting a comment) all
  go this way.
- **Calling into the server.** `callServer(module, export, args)` imports a module through the
  worker's runner (the same instance the app uses) and calls an export with JSON arguments. It's how
  tests open the fake database's gates, ask which queries are waiting, or change data behind the
  app's back ("another user added a comment"). Test-only control modules live in the app's `tests/`,
  so the app itself has no test hooks.
- **The first page**: the HTML response is read as the bootstrap would, rows taken from the inline
  scripts and the rest checked to be the shell, so the HTML path is covered without a browser.
- **Entrypoints** load through the real reference map; `page->WeftTesting.holdLoads` holds them, to
  test a slow chunk.
- **Rendering** goes through `WeftDom.Client.act`, so effects have run when `settle` returns.
- **Checking an update was in place**: `page->WeftTesting.snapshotNodes` records the DOM nodes under
  the container, and `WeftTesting.sameNodes(before, after, ~except=?)` asserts that every one is
  still the same node, except those named; `WeftTesting.renderCount(page, ~id)` counts an
  entrypoint's renders (the harness wraps each loaded `make`).
- **`Build` mode** runs the same tests against `vp build`'s output: the worker imports
  `dist/server/index.js`, and the client loads the built chunks from `dist/client` by way of the
  manifest, instead of the sources.

**Proving it out first.** This leans on less-trodden Vite APIs: a module runner in a worker with a
custom transport, and Vitest applying a plugin's client environment to the test's own graph. Phase 5
starts with a spike of two files (one server component, one entrypoint) through the whole harness.
If it fights back, the fallback is two module runners in one thread: module instances are still
separate, but globals aren't, so server code could see jsdom's `document`, which a development-mode
guard in `Render` (fail if a server component touches `document` or `window`) would then have to
catch.

#### Example apps

Both are Vite apps served by `@e-cline/server`, with their data behind an interface the tests
replace: a fake database, in the server's realm, whose queries each wait on a named gate the test
opens through `callServer`, so the order things finish in is the test's choice, not a timer's. In
`vp dev` the gates are timers instead, so the streaming is visible by hand; in the browser tests, a
test-only route opens them.

**`examples/weft_notes`**: the integration test bed, using every feature in a small notes app: a
list page and a note page with three boundaries (the note, its comments, related notes), a
`LikeButton` entrypoint with state, a comment form entrypoint that posts to a route and calls
`refresh()`, a `CommentList` entrypoint receiving its comments as a promise prop, a `NoteEditor`
entrypoint (a draft in state, the saved title and "saved at" time as props) whose save posts and
refetches the note's header frame, the comments in a `Frame` with a reload button, a server
component that fails inside an error boundary, and links that `navigate`. Its tests, through the
tier 2 harness, from source:

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
- saving in `NoteEditor` refetches the header frame: the new title and "saved at" arrive as props,
  the draft and the input's focus and selection are kept, the input is the same DOM node, and
  nothing outside the frame changes (`sameNodes`, render counts);
- reloading the comments frame after another "user" adds a comment through the fake database: the
  new comment is inserted, the existing comment nodes are kept, and a comment whose text was edited
  is updated in place;
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

- **the build**: `vp build`, then assertions on the manifest and `dist/client`: each entrypoint file
  is its own chunk, the shared module is a chunk both import, the large module is only in the chunk
  of the entrypoint using it, and the server sentinel is nowhere;
- **the built app, through the harness** (`Build` mode): every route renders, and only the chunks a
  page uses are loaded;
- the same scenarios in `Source` mode, so a difference between dev and build shows up as one passing
  and the other failing.

#### Tier 3: browser smoke tests (`examples/weft_notes/e2e`)

A few Playwright tests (`@playwright/test`, Chromium only) against `weft_notes` built and served
over real HTTP on a free port, with a test-only route to open the gates, enabled by an environment
variable the test server sets:

- the first page streams: the shell and row 0 show, then each boundary fills in as its gate opens;
- an entrypoint's chunk is requested only once a page uses it, and once only (from the network log);
- saving in `NoteEditor` refetches its frame and keeps the input's focus and selection;
- navigating between notes keeps the like button's state, and the back button works.

They run in CI on one Node version, as a task of their own (`vp run e2e`), since they need a browser
installed. They're few by design: anything that can be checked in tier 2 is, and these cover what
only a browser can show. Phase 6 adds hydration's (no flash of client rendering, the server's nodes
kept).

## Packages and layout

```
tools/ppx/setup.sh, rescript_ppx.opam.locked   the shared OCaml toolchain (moved from pretty_print)
tools/ppx/weft/                    @e-cline/ppx_weft: ppx_src/ppx_weft.ml, bin/main.ml, ppx script
packages/weft/src/Weft.res(i)      gains a `Lazy` alias (useful in client-only apps too)
packages/weft_core/src/
  Lazy.res(i)                      `Lazy.fromPromise`; Element.kind gains `Lazy`
  Entrypoint.res(i)                `mark` (what the PPX calls) and `idOf`, for renderers
packages/weft_server/              namespace WeftServer
  src/Payload.res(i)               the row and value encoding, shared by both ends
  src/Render.res(i)                server renderer: element => ReadableStream
  src/Client.res(i)                stream => elements; navigate, refresh
  src/Page.res(i)                  the HTML shell with inlined rows
  src/Frame.res(i)                 the built-in entrypoint for refetching part of a page
  src/Testing.res(i)               tier 1 helpers: a stub stream, entrypoints served from a map
packages/vite_plugin_weft/         @e-cline/vite_plugin_weft (TypeScript)
  src/testing/                     the tier 2 harness (`/testing` export): Vite server, worker, port
  src/WeftTesting.res(i)           its ReScript bindings
  tests/fixtures/                  small apps with hand-written "compiled" files
tools/ppx/weft/tests/              fixtures that compile, fixtures that don't, compiler canaries
examples/weft_notes/               notes app: the integration test bed (§9)
  tests/                           tier 2 scenarios, and the fake database's control module
  e2e/                             tier 3 Playwright tests
examples/weft_split/               code-splitting edge cases, tested built and from source (§9)
```

Each package gets the usual wiring: root `rescript.json` `dependencies` and a `workspace:*` root
`devDependency` for the ReScript ones, a README row, error codes in its README, and a changeset.

## Phases

Each ends green (`pnpm run build`, `pnpm run test`, `pnpm run check`) and is a reviewable PR.

**Phase 0 -- Pin what the compiler does.** A `ppx_weft` that only replaces `@weft.component` with
`@jsx.component`, the PPX test package with the compiler canaries and the first good fixtures (§9),
and the opam setup moved to the shared switch.

**Phase 1 -- `WeftCore.Lazy` and `Entrypoint`.** The new element kind, unwrapped in
`ChildReconciler`; `Entrypoint.mark`; the server-render flag in `HookImpl`; with their tests (§9).

**Phase 2 -- The PPX in full.** Async rewriting, marks, ids, directives and every error in §2, with
the rest of the PPX's fixtures, good and bad (§9).

**Phase 3 -- Wire format and renderer, no bundler.** `Payload`, `Render` and `Client`, each tested
on its own and then together into the TestRenderer, including every in-place update test and the
update fuzz test (§9), with `fetchElement` and request ordering. `WeftServer.Testing` (the tier 1
helpers) comes with them.

**Phase 4 -- The Vite plugin, and `weft_split`.** Environments, the virtual modules, the scan, the
boundary check, the dev middleware and the build, with the plugin's unit, build and dev tests on its
fixtures. Then `examples/weft_split` and its build tests, the first time the real PPX output goes
through the plugin. (Its harness tests wait for phase 5.)

**Phase 5 -- Pages, navigation, the harness and `weft_notes`.** First the tier 2 spike (§9), which
decides between the worker and the one-thread fallback. Then `Page`, the bootstrap,
`navigate`/`refresh`, `Frame` and `useFrame`, and server HMR; the tier 2 harness and its bindings;
`examples/weft_notes` with its scenario tests; `weft_split`'s harness tests, from source and built;
and the tier 3 browser tests, with the `e2e` task wired into CI.

**Phase 6 -- HTML and hydration** (§8): the hook-less HTML renderer, streaming Suspense HTML, then
hydration in the reconciler and the DOM host. Could be its own plan once phases 1--5 have settled.
The harness carries over: the first page's HTML is put into the container before the client starts,
and `weft_notes`' scenarios are run again checking that hydration reused the server's nodes; the
browser tests check the same in Chromium.

Out of scope: server functions/actions (mutations go through ordinary routes, then `refresh()`), the
Flight wire format and interop with React, CSS handling beyond what Vite does already, shared
references and cycles in payloads, context on the server, and caching rendered output.

## Risks and open decisions

- **The PPX depends on compiler details**: that external PPXs run before the JSX transform, and the
  AST encoding ppxlib 0.34 reads. Phase 0's tests exist to catch a ReScript upgrade changing any of
  these.
- **A missing PPX fails loudly, but unclearly.** Without `ppx_weft` in `ppx-flags`,
  `@weft.component` is ignored and every use of the component is a type error about `component<'a>`
  (verified point 2), which doesn't say what's wrong. Nothing builds, so it can't ship; the README
  should lead with the setup, and list that error as its symptom.
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
  client environment inside Vitest), which could change or not quite work. The phase 5 spike finds
  out before anything is built on it; the fallback (§9) loses only the separation of globals.
- **Tiers 1 and 2 never run real HTML streaming or chunk loading.** The browser tests do, but only
  for a few scenarios, so a browser-only problem elsewhere could get through. Keeping the first
  page's HTML reading in tier 2 identical to the bootstrap's (one shared module) narrows it.
- **Naming**: `weft_server` sits next to `@e-cline/server` (HTTP); `weft_rsc` is the alternative.
  `kind: Entrypoint` could equally be `kind: Client`; "entrypoint" says more precisely that it's
  where client code starts, and everything it imports comes along.
