# Plan: server-rendered HTML and hydration for Weft

Today a Weft page's first response is a shell with an empty `<div id="root">` and the payload's rows
as inline scripts: nothing shows until the bootstrap has loaded, decoded the rows, loaded the
entrypoints' chunks and rendered. This plan adds the rest of what a first paint needs:

- **HTML on the server.** The page's first response carries the page as HTML, entrypoints included
  (rendered with their initial state), streamed: everything outside `Suspense` boundaries first (the
  shell), then each boundary's content as it's ready, swapped in over its fallback by a few bytes of
  inline script. The page reads, and its links and layout work, before any JavaScript runs.
- **Hydration on the client.** The bootstrap renders the same element tree over that HTML, adopting
  the server's nodes instead of creating new ones: attaching event handlers, setting up state and
  running effects. A boundary whose content hasn't arrived yet stays as the server left it, and is
  hydrated once its HTML is swapped in.

It's phase 7 of [the server components plan](weft_server_components_plan.md) (§9 there sketches it),
and builds on everything phases 1 to 6 left: the payload and its decoder, `Page`, `Bootstrap` and
`Navigation`, the Vite plugin, the tier 2 harness and `weft_notes`. Navigation after the first page
doesn't change: it fetches payloads, as now.

```
request ──► Render.toStream (server components run, once)
              │ payload rows
              ├──────────────► the page: <script>__weft.push(row)</script>, for the client
              ▼
            Decoder.fromStream, on the server (entrypoints imported there)
              │ the element tree the browser will decode, row for row
              ▼
            WeftDom.Html.renderToStream (entrypoints called, with their initial state)
              │ HTML: the shell, then each boundary's segment
              ▼
            the page: <div id="root">shell</div>, rows, <template>segment</template><script>swap</script>

browser:    HTML paints as it streams ──► bootstrap: rows → elements → hydrateRoot(#root)
```

## Status

Not started. This document is the plan, and its decisions are settled (Decisions, at the end). The
phases (7.0 to 7.6, then the follow-ups 7.7 and 7.8) go on the same branch as phases 0 to 6, a
commit or a few each, each ending green, with a review before the next.

## What was verified before writing this

Spikes, against the code as phase 6 left it (scripts in the session's scratchpad, not committed):

1. **An entrypoint's hooks run on the server without the reconciler**, through `weft_core`'s own
   mount path: `HookImpl.renderWithHooks(None, fiber, component, props, lane)` on a fiber that's in
   no tree. In Node, with no DOM: `useState` and `useReducer` give their initial state, `useRef`,
   `useMemo` and `useCallback` work, `useContext` reads the context's `currentValue` (which the
   renderer sets around the call), `useEffect` and `useLayoutEffect` record effects that never run,
   `useTransition` gives `(false, _)`, `useDeferredValue` its value, a render-phase update renders
   again (derived state, as React allows), and `Hooks.use` on a pending promise throws `Suspended`.
   An update made after the render reaches no root (`FiberRoot.scheduleUpdate` walks up from the
   fiber and finds none) and is dropped. Two things need a wrapper (§2): `useSyncExternalStore`'s
   reads accumulate in a global list (`HookImpl.storeChecks`) that nothing clears, and a component
   that throws (or suspends) leaves `HookImpl.state` pointing at its fiber, which the reconciler
   resets in its own `catch`.
2. **What the HTML parser does to markup**, in jsdom (the tier 2 harness's DOM), each of which the
   renderer or the hydrator has to allow for:
   - adjacent text merges into one text node (`a` then `b` is `"ab"`), and `a<!-- -->b` keeps them
     apart, as two text nodes and a comment;
   - an empty text node doesn't exist in HTML (`<p></p>` has no child);
   - invalid nesting is repaired: `<p>x<div>y</div></p>` parses as `P DIV P`;
   - `<table><tr>` gets a `<tbody>` it didn't have;
   - a `<textarea>`'s first newline is dropped;
   - comment markers (`<!--$?-->`) and an empty `<template>` survive as nodes.
3. **A boundary's content can go in a `<template>` in any context**:
   `<template><tr>…</tr></template>` keeps its row (in `template.content`), where a `<div hidden>`
   wrapper loses it (the row is dropped and only its text is left). React wraps by context; a
   template works everywhere.
4. **jsdom can't parse a document that arrives in pieces**: `document.write` in chunks, with inline
   scripts between, doesn't run the later scripts as a browser would. The harness applies a page's
   HTML piece by piece itself (§9), as it already pushes the rows itself.
5. **Entrypoints read the page from context**: `Navigation.useNavigation` (and so `Rpc.use`,
   `useRefetchable`) fails outside `Navigation.show`'s provider. Rendering entrypoints on the server
   needs a page there too (§2).
6. **`Bootstrap.start` renders with `createRoot`, which empties `#root`**: the one call to change on
   the client for hydration, beyond the reconciler.

## How it works, end to end

1. A request for a page comes in. `Page.respond` writes the document's head (the bootstrap's script,
   `async`, and its preloads) at once.
2. `Render.toStream` renders the element tree as today: server components run, once, and the payload
   streams out. The page tees it: one branch goes to the page as row scripts (as today), the other
   to a `Decoder` on the server (today's `WeftServer.Client`, renamed in phase 7.0), which decodes
   it into elements exactly as the browser will, importing entrypoint files from the server's own
   copy of the reference map (`virtual:weft/ssr-references`).
3. `WeftDom.Html.renderToStream` renders the decoded tree to HTML: host elements as tags, text as
   text, entrypoints and shared components called (their hooks giving initial state, their effects
   not running), providers providing. A `Lazy` element (a row that hasn't arrived) or a `Hooks.use`
   on a pending promise suspends, as on the client: outside every boundary, the shell waits for it;
   under one, the boundary's fallback is written in its place, with markers, and its content follows
   later.
4. Once the shell is ready, the page writes `<div id="root">` with the shell's HTML inside, then the
   row scripts held back until now, then each row as it comes. When a boundary's content is ready,
   the page writes it in a `<template>` and an inline script that swaps it in over the fallback.
5. The browser paints the shell as soon as it arrives, and each boundary's content when its swap
   runs, whether or not the JavaScript has loaded.
6. The bootstrap (once its chunk has loaded) decodes the rows as today, and with the root row in,
   calls `WeftDom.Client.hydrateRoot(#root, element)`. The reconciler renders the tree, but instead
   of creating host nodes it walks the server's: each host element claims the next node in the DOM
   if its tag matches, attaches its event handlers and stores its props; each text claims a text
   node. Effects run after the commit, as after any mount. The page is interactive.
7. A boundary the server hadn't finished (still showing its fallback when hydration reaches it)
   isn't rendered on the client yet: it stays as the server's HTML until its swap runs, and is then
   hydrated in turn. One that's already been swapped in hydrates with the rest.
8. A mismatch (the client's tree and the server's HTML disagree) is a development-build warning. A
   text that differs is patched; a structural one (a missing node, another tag) gives up on the
   nearest boundary: its server HTML is removed and its content rendered on the client from scratch.
9. From then on the page is a client-rendered one: `navigate`, `refresh`, refetching and RPCs work
   as they do now.

## Design

### 0. Client and server code, kept apart

Phase 7 makes the question "where does this run?" harder: entrypoints start running on the server,
the payload decoder (`WeftServer.Client`) runs on both sides, and an HTML renderer joins the DOM
renderer. Today the packages don't say: `weft_server` has the browser's bootstrap in it, `Rpc` has
the client's `call` and the server's `router` in one module, and "Client" means two different things
(`WeftDom.Client`, a DOM root; `WeftServer.Client`, the payload decoder, which isn't only the
client's any more). Phase 7.0 sorts this out before anything is added, so each module says where it
runs, and the build checks it:

- **Each package's `src` has `client/`, `server/` and `shared/`** (and `testing/` for the test
  helpers). ReScript module names don't depend on directories, so this moves files without renaming
  modules (except as below).
  - `weft_core`: everything is `shared/` (the reconciler, hooks, elements, `ServerRender`), except
    `TestRenderer`, `TestScheduler` and `TestJsx` in `testing/`.
  - `weft_dom`: `client/` has `Client` (roots) and `DomHost`; `server/` has `Html` (the HTML
    renderer, §3); `shared/` has `Dom`, `DomProps` (the prop rules both renderers follow), `Jsx` and
    `Portal` (a portal element can be made anywhere, and renders nothing on the server).
  - `weft_server`: `client/` has `Bootstrap`; `server/` has `Render`, `Page` and `RpcServer`;
    `shared/` has `Payload`, `Decoder`, `Navigation`, `Rpc`, `RpcCodec` and the internals;
    `testing/` has `Testing`.
- **Server-only modules are marked `@@weft.server`** (`Render`, `Page`, `RpcServer`, `Html`), the
  attribute phase 6 added for apps' own server files, so the plugin refuses them to an app's client
  build and names the chain of imports, exactly as it does an app's server files. The packages
  compile through `ppx_weft` for this (it writes nothing else into a file without Weft's
  attributes). Browser-only code (`Bootstrap`, `DomHost`) is harmless to import on the server (it
  only touches `document` when called), so it isn't marked; calling it there fails at once, in
  tests.
- **`Rpc` is split in two**: `Rpc` (shared: `t`, `make`, `makePrepared`, the errors, `call`, `use`)
  and `RpcServer` (`handler`, `router`, `respond`, `ids`). An RPC's handler file then imports a
  server-only module, which says what it is; and the client build no longer carries the router.
- **`WeftServer.Client` becomes `WeftServer.Decoder`**: it decodes payloads into elements, in the
  browser and (from phase 7.5) on the server. `WeftDom.Client` keeps its name: it's the DOM's roots,
  client-only.
- **Each package's README gets a "Where it runs" table**: every public module, and client, server or
  both.

Nothing changes in behaviour; the tests move with their modules and pass as they are, apart from the
renames. The package names stay (`weft_server` is "server components", client half included), as
decided before phase 0.

### 1. Rendering from the decoded payload

The HTML is rendered from the payload decoded on the server, not from the element tree `Render`
walks. That's what React does (Fizz renders what the Flight client decoded), and for the same
reasons:

- **Server components run once.** Rendering HTML from the original tree would call every server
  component a second time (and wait on its database queries again), or need `Render` to produce HTML
  and payload at once from one walk, which tangles the two.
- **The tree is the browser's, exactly.** Hydration only works if the client renders the same tree
  the HTML came from. Decoding on the server with the same `Decoder` means the HTML is rendered from
  the tree the browser will decode, row for row: server components' output as values, keyed ones in
  their fragments, props as they came out of JSON (an `undefined` field gone, a date a new `Date`),
  entrypoints as the components the reference map loads. Nothing has to be kept in step by hand.
- **Errors arrive the same way.** A server component that failed under a boundary is an `X` row;
  decoded, it's a rejected `Lazy`, which throws where it stands, on the server as in the browser.

The cost is encoding and decoding the payload once more, on the server: JSON in memory, linear in
the payload's size, and small next to rendering.

**Where it runs: in the `rsc` environment.** The server's `Decoder` imports entrypoint files there,
through a new virtual module, `virtual:weft/ssr-references` (the same map as the client's
`virtual:weft/client-references`, imported by the server), so the server build bundles the
entrypoint files too. React's Vite plugin has a third environment (`ssr`) for this, because React
has two builds (the `react-server` export condition) that can't share a module graph. Weft has one
`weft_core`, so one server environment is enough: one server build, one module graph, one copy of
each shared module. What it asks of entrypoint files: no DOM access at the top level of a module
(only in handlers and effects), which is already true of every one in the repo, and the same rule
React has.

### 2. Hooks without the reconciler

`weft_core` gains `ServerRender.renderComponent(component, props, options)`, for server renderers
that call client components (entrypoints, and the shared and client components they render): it
calls the component through `HookImpl.renderWithHooks` on a fiber made for the call and in no tree,
as a mount (verified point 1). On top of what the spike showed works, it:

- sets aside any render in progress (as `ServerRender.run` does today), and restores it however the
  call ends, resetting `HookImpl.state` after a throw or a suspension;
- clears the store reads `useSyncExternalStore` recorded, which only the reconciler's commit checks;
- sets each context in `options.contexts` (the providers above, as the walk has them) as its
  `currentValue` for the synchronous call, and puts the previous values back after. The HTML
  renderer is asynchronous (siblings render concurrently, §3), so `ContextImpl`'s push/pop stack
  can't be used: each call gets its contexts explicitly, from an immutable list the walk carries.

The hooks behave as they would on a first render that never commits: initial state, no effects,
updates dropped. Two need changes of their own:

- **`useSyncExternalStore`** gains `~getServerSnapshot`, as React's has: the server renders with it,
  and so does hydration (the HTML was rendered from it), with an update straight after to the
  client's snapshot if it differs. Without it, rendering on the server fails with an error saying to
  give one (a new `weft_core` code, 15).
- **`Hooks.use`** already works on both sides.

`ServerRender.run` (server components, which must not have state) is unchanged: its hooks still fail
with error 14. The two are different calls on purpose: a server component that used `useState`
should still be told it can't.

**The page on the server.** Entrypoints read their page from context (`useNavigation`, and through
it `Rpc.use` and `useRefetchable`). `Page` renders the HTML inside `Navigation.show`'s provider,
with a server-side `Navigation.t`: its URL is the request's, its decoder the server's own, and
calling `navigate` or `refresh` on it fails (they're for handlers and effects, which don't run on
the server). `Navigation` gains `Navigation.makeForServer(decoder, ~url)` for this.

### 3. The HTML renderer: `WeftDom.Html`

A new module in `weft_dom`'s `server/` (§0), marked `@@weft.server`. It's in `weft_dom` because it
follows the same prop rules as `DomHost` (in `shared/DomProps`), and doesn't depend on
`weft_server`: a client-only app could use it for static pages.

```rescript
/** The HTML for `element`, streamed: the shell, then each boundary's content as it's ready. */
let renderToStream: (
  WeftCore.Element.t,
  ~onError: exn => option<string>=?,
  ~signal: AbortSignal.t=?,
) => stream

/** The HTML for `element`, all of it, once everything has rendered (for tests, and static pages). */
let renderToString: WeftCore.Element.t => promise<string>
```

It walks the tree like `Render`, with no fibers, by element kind:

- **Text and numbers**: escaped text. Two texts in a row get `<!-- -->` between them, which the
  hydrator skips (verified point 2). An empty string writes nothing; the hydrator makes its node
  (§6).
- **`Host`**: the tag (checked: `[a-z][a-z0-9-]*`), its attributes (below), its children, the
  closing tag. Void elements (`input`, `br`, `img`, …) have no closing tag and can't have children.
- **`Component` and `Memo`**: called through `ServerRender.renderComponent` (§2), and the output
  rendered. A suspension waits for the promise and calls it again, as `Render` does (with the same
  retry limit).
- **`Fragment`**: its children. **`Provider`**: its children, with its value added to the walk's
  contexts.
- **`Suspense`**: the unit of streaming (§4).
- **`Lazy`**: what it resolves to; until then, a suspension, as on the client.
- **`ErrorBoundary`**: its children. It doesn't catch on the server: its fallback would be what the
  HTML shows, and the client, rendering the children, would never match. An error goes to the
  nearest `Suspense` boundary, which is left for the client to render (§8), where the error is
  thrown again and the `ErrorBoundary` catches it there. With no boundary above, the shell fails,
  and the page falls back to rendering on the client (§5).
- **`Portal`**: nothing. Its children go in another container, which the page's HTML doesn't have;
  the client renders them after hydrating (§6).
- **`Offscreen`**: never in an element tree (it's the reconciler's): an error, as in `Render`.

**Props are applied by one set of rules on both sides.** `DomProps` gains the rules `DomHost` now
has inline (`attributeName`, `isEventProp`, how `style`, `value`, `checked` and booleans are
written), and the HTML renderer and `DomHost` both use them, so what the server writes is what the
client would have set:

- event handlers (`on*`) and `ref` are left out (the hydrator attaches them);
- `true` writes the attribute empty, `false` and absent leave it out, anything else is its string,
  escaped (`&`, `<`, `>`, `"`, `'`) in a double-quoted attribute;
- `style` writes a `style` attribute, each name in kebab case (`backgroundColor` as
  `background-color`; `--custom` as it is), each value escaped;
- `value` and `checked`, which the client sets as properties, are written as the attributes that
  give the same initial state: `value="…"` on an `input`, the text of a `textarea` (with a newline
  first if the value starts with one, since the parser drops the first, verified point 2), and
  `selected` on the `option` of a `select` whose `value` it is (the renderer keeps the enclosing
  `select`'s value in the walk, as React's does); `checked` as `checked`.

**What the parser would change, a development build warns about**, naming where it is (as `Render`'s
messages do): invalid nesting the parser repairs (a block element in a `<p>`, an `<a>` in an `<a>`,
a `<tr>` straight in a `<table>` with no `<tbody>`, from verified point 2). The HTML would otherwise
hydrate into a mismatch with no clue why. `<script>` and `<style>` with children fail: their
contents aren't HTML text, and Weft has no raw-HTML prop to write them with.

**Concurrency, as in `Render`.** Siblings render concurrently; a suspended component waits without
holding up the rest; output is buffered in order (a segment's HTML is written in tree order however
its parts finish) and flushed per macrotask. Aborting `signal` (the client went away) stops
everything pending.

### 4. Streaming: the shell, boundaries and segments

`Suspense` boundaries are the unit of streaming, as in `Render`. The shell is everything outside
every boundary, and goes out once all of it is ready. Under a boundary, if the content suspends, its
fallback is written in its place, and the content follows in a segment of its own once ready. If the
content doesn't suspend, it's written in place: no fallback, no segment.

**The markers**, comments the hydrator reads (and the swap script rewrites):

```html
<!--$-->content<!--/$-->
a boundary whose content is in place
<!--$?--><template id="wb:3"></template>fallback<!--/$-->
pending: its content is still to come
<!--$!--><template data-digest="…"></template>fallback<!--/$-->
it failed on the server (§8)
```

**A segment**, once boundary 3's content is ready:

```html
<template id="ws:3">content</template>
<script>
  $weftSwap(3);
</script>
```

`<template>` rather than a hidden `<div>`, so a boundary in a table, a list or a select works
(verified point 3). The segment can itself contain pending boundaries, whose segments come later.

**The swap runtime** is a few hundred bytes of inline script, written once, before the first
segment: `$weftSwap(n)` finds `wb:n`'s marker, removes the fallback's nodes up to the end marker,
inserts the template's content in their place, removes the template and the anchor, and rewrites the
marker to `$`. Then, if hydration has already reached that boundary and left it waiting (§6), it
tells it: the anchor's marker carries a callback (`marker.$weftRetry`) the hydrator set, which the
swap calls. The runtime's source lives in `weft_dom` (`Html.swapRuntime`), and its own tests run it
in jsdom.

**A boundary's segment waits for its rows.** The page writes payload rows as they come and a segment
once the HTML renderer has it; the renderer can only finish a segment once the rows it needed had
been decoded, so a segment's rows are always on the page before it. When the swap tells the
hydrator, the client has, or is about to have, the same rows.

### 5. The page

`Page.respond` (and `Page.toStream`) gain the HTML, with these rules, in order:

1. The head goes out at once, as now (the bootstrap's `async` script, its preloads, stylesheets).
2. The payload is teed: one branch is decoded on the server (§1), the other buffered.
3. When the HTML renderer's shell is ready, `<div id="root" data-weft-html>` goes out with the shell
   in it and `</div>`, then the buffered rows, then rows and segments as they come, in the order
   they're ready. Rows always follow the shell, so when the bootstrap sees the root row, `#root` has
   been parsed: there's nothing for it to wait on but the rows, as now.
4. A `modulepreload` for an entrypoint's chunk goes before the first row that uses it, as now, and
   also before the shell when the shell uses it, so the chunks load while the HTML parses.
5. The page ends once the payload has and the last segment has been written.

**If the shell fails** (an error with no `Suspense` boundary above it, in a server component or an
entrypoint), the page falls back to what it does today: an empty `#root` (no `data-weft-html`), and
the rows, for the client to render, and to throw the error where an `ErrorBoundary` can catch it.
`onError` sees the error. The page's status is still 200: the payload's root may well be fine, and
the client is the one to say.

**Opting out.** `Page.respond(~html=false)` writes the page as today, for routes where HTML on the
server isn't worth it (or while finding a hydration bug). The bootstrap tells which it got from
`data-weft-html`.

**What the server needs from the plugin**: `virtual:weft/ssr-references` (§1), allowed only in the
`rsc` environment, as `virtual:weft/assets` is; and the server build bundling the entrypoint files
it imports. In development, the `rsc` environment's module runner imports them from source, so a
change to an entrypoint file is picked up by the next request (and the client reloads, as now).

### 6. Hydration in the reconciler

`weft_core`'s reconciler learns to render over nodes that are already there.

**The host operations.** `HostConfig` gains a module type for hosts that can hydrate:

```rescript
module type Hydratable = {
  include S
  /** A node in the container's existing content, being hydrated. */
  type hydratable
  /** The first hydratable child of a container or an instance, skipping what the host ignores. */
  let firstHydratableChildOfContainer: container => option<hydratable>
  let firstHydratableChild: instance => option<hydratable>
  let nextHydratableSibling: hydratable => option<hydratable>
  /** `hydratable` as an instance for `tag`, if it is one. */
  let asInstance: (hydratable, ~tag: string) => option<instance>
  let asTextInstance: hydratable => option<textInstance>
  /** Attaches what the server couldn't write (handlers, the stored props); warns, in development, about attributes that differ. */
  let hydrateInstance: (instance, ~tag: string, ~props: props) => unit
  /** A `Suspense` boundary's markers, and what they say. */
  let asSuspenseInstance: hydratable => option<suspenseInstance>
  let suspenseState: suspenseInstance => [#complete | #pending | #failed]
  /** The first hydratable node inside the boundary, and the one after its end marker. */
  let firstHydratableInSuspense: suspenseInstance => option<hydratable>
  let nextHydratableAfterSuspense: suspenseInstance => option<hydratable>
  /** Calls `retry` once a pending boundary's content has been swapped in. */
  let onSuspenseReady: (suspenseInstance, unit => unit) => unit
  /** Removes the server's nodes between a boundary's markers (to render it on the client). */
  let clearSuspense: suspenseInstance => unit
  /** Removes a node hydration didn't claim. */
  let removeHydratable: hydratable => unit
}
```

`Reconciler.Make(Host)` stays as it is for hosts that can't (and gives them no hydration code), and
`Reconciler.MakeHydratable(Host)` gives the same API plus
`hydrateRoot: (container, Element.t) => root`. Internally both are one functor, over a hydration
module that's either the host's or a stub.

**The walk.** While a root (or a boundary, below) is hydrating, the reconciler keeps a cursor: the
next hydratable node in the host parent being hydrated. In `beginWork`, a host element mounting (no
`current`) claims the cursor's node if it's an instance of the same tag, moves the cursor to that
node's first child, and its children hydrate inside it; in `completeWork`, instead of
`createInstance` and `appendAllChildren`, it calls `hydrateInstance`, removes any nodes left after
its last claimed child, and moves the cursor to the node's next sibling. Text claims a text node. A
fiber that claimed its node gets no `placement` flag: its node is already where it goes. Function
components, fragments, providers and the rest have no node and claim nothing, so the server's flat
HTML lines up with the client's deeper tree.

- **Text.** Adjacent texts are kept apart by the server's `<!-- -->`, which `nextHydratableSibling`
  skips. A text whose content differs is patched (`commitTextUpdate`) with a warning, rather than
  treated as a structural mismatch: dates and times rendered on the server are the usual cause, and
  the rest of the page is fine. An empty text, which the HTML can't have (verified point 2), claims
  nothing: its node is created and placed as on a normal mount.
- **Portals** claim nothing: their children mount into their own container as on a normal mount.
- **Errors** thrown while hydrating go to error boundaries as on any render; an `ErrorBoundary` that
  catches one discards the hydration of its subtree (the fallback has no server HTML) and renders
  the fallback on the client.

**`Suspense` boundaries.** A `SuspenseComponent` mounting while hydrating claims a boundary's
markers, and by what they say:

- **complete** (`$`): its content hydrates inside the markers, with the cursor at the first node
  after `<!--$-->`, and moves on after `<!--/$-->` when it completes.
- **pending** (`$?`): the boundary is _dehydrated_. It renders nothing on the client (neither
  fallback nor content), keeps the server's nodes as they are, and registers `onSuspenseReady`. When
  the swap runs, the boundary is scheduled to render again, and hydrates its content then, now that
  it's complete. A dehydrated boundary is a fiber state of its own (`SuspenseComponent` whose
  `memoizedState` holds the `suspenseInstance`), so nothing below it has fibers until then.
- **failed** (`$!`): the server's nodes inside are removed (`clearSuspense`), and the boundary is
  rendered on the client as a fresh mount (fallback first, if its content suspends).

**Suspending while hydrating.** A component in a hydrating boundary that suspends (a `Lazy` whose
row hasn't arrived, a `Hooks.use` on a pending promise, an entrypoint whose chunk is still loading)
leaves that boundary dehydrated, with the server's HTML still showing, and tries again when the
promise settles: never the client's fallback over content the server already sent. At the root
(outside every boundary), hydration renders in a transition lane, so a suspension there waits, the
whole render waiting with the server's HTML still on screen (the rule today's transitions already
follow), instead of failing for want of a boundary.

**Updates before a boundary has hydrated.** If new props reach a dehydrated boundary (a `navigate`
or `refresh` rendering the page again before the boundary's content had arrived), it stops waiting:
its server nodes are removed and it renders on the client like any new boundary. React instead
hydrates it at once at a higher priority; doing that here can come later, and only matters for a
navigation during the first page's streaming.

**Mismatches.** A host element that finds no node where it expected one, or one of another tag (or
text where an element was), is a structural mismatch. Hydration of the nearest `Suspense` boundary
is abandoned: the render unwinds to it (as an error does to an error boundary), its server nodes are
removed (`clearSuspense`), and it's rendered on the client as a fresh mount. With no boundary above,
the whole root is: the container is emptied and the tree mounted into it, which is what happens
today. Either way a development build warns, naming the component path and what was expected and
found. Nodes left over after a parent's last child are removed, with the same warning.

**Effects** run after the hydrating commit as after a mount: layout effects and refs (whose
`current` is the adopted node) synchronously, passive effects later. An entrypoint that reads the
DOM in an effect sees the server's nodes, which are now its own.

### 7. Hydration in the DOM

`DomHost` implements `HostConfig.Hydratable`:

- **Hydratable nodes** are elements and text, skipping comments that aren't boundary markers (the
  `<!-- -->` separators) and the boundary anchors (`<template id="wb:…">`). Weft writes no
  formatting whitespace, so every text node in the HTML is one of the tree's.
- **`hydrateInstance`** attaches the element's handlers (`setHandler` for each `on*`), stores its
  props, and, for `value` and `checked`, leaves what the user has typed or ticked since the HTML
  arrived (a controlled value set on the first update, not over the user's input on hydration, as
  React does). In development, it compares the element's attributes with what the props would write,
  and warns about each difference, without changing them (an extension's attributes, say, are left
  alone).
- **Markers**: `asSuspenseInstance` reads `$`, `$?` and `$!`; `onSuspenseReady` sets the marker's
  `$weftRetry` for the swap runtime (§4), or calls back at once if the swap already ran.
- **`WeftDom.Client.hydrateRoot(container, element)`**, beside `createRoot`: a root that hydrates
  the container's content on its first render, and is an ordinary root after.

`Bootstrap.start` calls `hydrateRoot` when `#root` has `data-weft-html`, and `createRoot` otherwise
(the shell failed, or the route opted out). `Navigation.show`'s first render is the hydrating one.

**Events before hydration.** Weft attaches a listener to each element, so until an element has
hydrated, its handlers aren't there: a click on it does nothing (a link still navigates, as a plain
link; a form submits as an HTML form would, to its `action`, or by default to the page itself).
Phases 7.1 to 7.6 leave it at that; replaying those events once their elements hydrate is designed
in §10, and comes after as phase 7.7. Nothing before it has to change for it.

### 8. Errors and mismatches, together

- **A server component fails under a boundary**: an `X` row, as now. The HTML renderer hits it and
  writes a failed (`$!`) boundary; the client renders that boundary, the error is thrown there, and
  an `ErrorBoundary` catches it.
- **An entrypoint (or a shared component) throws under a boundary** on the server: the same, with
  `onError` seeing it.
- **Either, outside every boundary**: the shell fails, and the page is today's (§5): the client
  renders it with `createRoot`, and the error is thrown where it's thrown today.
- **A text differs**: patched, with a warning in development.
- **A node is missing, or has another tag**: the nearest boundary (or the root) renders on the
  client, with a warning.
- **An attribute differs**: a warning in development; the attribute is left as the server wrote it.

In production, mismatches are recovered from the same way, without the warnings. `$!` boundaries
carry `onError`'s digest, and the message in development only, as `X` rows do.

### 9. Testing

The oracle throughout is the client render: **hydrating server HTML must end in exactly the DOM a
client render of the same tree makes**, with the server's nodes reused (none created, none removed)
whenever the two agreed.

#### `weft_core` (the reconciler, without a DOM)

`TestRenderer` implements `HostConfig.Hydratable`, with `TestRenderer.fromMarkup` building a node
tree from its own `toString` format (`<b id="c1">c1:0</b>`, with comments for markers), so the
hydration algorithm is tested in Node, fast, and fuzzed:

- **Unit tests**: hydrating nested hosts, text (adjacent, empty, differing), fragments, providers,
  memo, keyed lists; nothing created (`TestRenderer`'s count of `createInstance` calls is 0) and no
  placements; effects and refs after the commit; a host element, text, or a whole subtree missing or
  extra, at the root and under a boundary, and what's rendered on the client instead; complete,
  pending and failed boundaries; a pending boundary hydrating when told; suspending while hydrating
  (the server's nodes kept, the client's fallback never shown); an update reaching a dehydrated
  boundary; error boundaries catching during hydration; portals.
- **A fuzz test**: random trees (as the existing fuzz tests make them, with `Suspense`,
  `ErrorBoundary`, text runs and keyed lists), rendered once directly to markup, then hydrated over
  that markup: the result must equal the direct render, with no node created. Then the same with the
  markup mutated at random (a node removed, a tag changed, text changed): the result must still
  equal the direct render, and the warnings name the mutation.
- **`ServerRender.renderComponent`**: every hook, as the spike checked, and the wrapper's resets
  (store reads cleared, state reset after a throw or a suspension, a render in progress set aside).

#### `weft_dom` (HTML, and hydration in jsdom)

- **The HTML renderer**: escaping (text, attributes, `</script>` in text), void elements, booleans,
  `style`, `value` and `checked` on each kind of input, `textarea`'s newline, `select`'s `selected`,
  adjacent text separators, nesting warnings, providers, entrypoint-style components with state,
  suspension and retries, boundaries' markers and segments in order, errors under and outside
  boundaries, abort.
- **The swap runtime**, in jsdom: segments in order and out of order, nested, in a table, the retry
  callback before and after the swap.
- **Round trips**: `renderToString(element)` into a container, then
  `hydrateRoot(container, element)`: the container's nodes are the same objects after as before (a
  snapshot, as the harness's `removedSince`), handlers work, `innerHTML` is unchanged, and there are
  no warnings.
- **A fuzz test**: random DOM trees (tags, attributes, styles, inputs, text runs, boundaries with
  async content), `renderToStream` cut into random chunks and applied as the page would (shell, then
  segments and swaps), hydrated at a random point along the way: in the end the DOM equals a
  `createRoot` render's, node for node, with no warnings, and the nodes from the HTML were reused.

#### `weft_server`

- `Page`'s HTML: the shell inside `#root`, rows only after it, segments after their rows, preloads
  before the shell for its entrypoints, a failed shell falling back to today's page, `~html=false`,
  and the server-side `Navigation.t` (an entrypoint calling `useNavigation` renders; one calling
  `navigate` while rendering fails).
- End to end in one process: `Render` → `Decoder` → `WeftDom.Html` → jsdom → `Bootstrap` hydrating,
  against `Support.serve`, with deliveries the test controls.

#### The plugin and the harness

- `virtual:weft/ssr-references` in the `rsc` environment only; the server build bundling the
  entrypoint files; in development, an entrypoint's change picked up by the next page.
- **The harness gains HTML**: `openPage` applies the page's HTML as a streaming parser would (which
  jsdom can't, verified point 4): the shell into the container, then each row and each segment, with
  its swap, in the order they arrived, as the delivery mode allows. `page.hydrated` waits for the
  bootstrap's hydration, `page.htmlNodes` snapshots what the HTML made, and `page.warnings` collects
  the console's mismatch warnings. A page can be opened with JavaScript off (`~bootstrap=false`), to
  check what the HTML alone shows.

#### Example apps

- **`weft_notes`'s scenarios run again with hydration**: each first page checks that its nodes are
  the HTML's (`removedSince` empty across hydration), with no warnings, before the scenario goes on.
  New ones: the first page readable without JavaScript (title, body, comments once their gates
  open), boundaries swapped in before the bootstrap runs and after, a gate opening while hydration
  waits on a boundary, the like button working after hydration, a failing component's box rendered
  on the client, and a mismatch provoked on purpose (a component rendering the time) patched and
  warned about.
- **`weft_split`**: a hydrated page loads only the chunks its entrypoints need, in development and
  built.
- **Browser tests** (Chromium): the page's text visible with JavaScript disabled; a boundary's
  content painted before the bootstrap has loaded (the bootstrap's chunk held back by a route);
  clicking after hydration works, and no console errors or warnings; and the existing four tests,
  now over hydrated pages.

### 10. Event replay (phase 7.7, a follow-up)

Recording the events that happen before their elements have hydrated, and dispatching them again
once they have, as React does for "discrete" events. It's additive: it needs nothing from phases 7.1
to 7.6 beyond what they already have (an inline runtime in the page, and hydrated elements carrying
their stored props), so it's planned here and built after.

**What's recorded.** The page's inline runtime (§4's, written in the head, before the shell) adds
capture-phase listeners on `document` for `click`, `submit`, `input` and `change`. An event is
recorded only if its target is inside `#root` and not hydrated yet: the nearest element at or above
the target has no stored props (`DomHost` stores them on every element it creates or hydrates, so
having them is what "hydrated" means, at the root and in a dehydrated boundary alike). Events on
hydrated elements are left alone, to reach their handlers as usual.

**Default actions**, which happen whether or not the event is recorded, and are only sometimes what
the page wants:

- A `click` on a link (`<a href>`) isn't recorded: the browser follows it, as it would with no
  JavaScript. (A `Link` entrypoint would have navigated in place; following it costs a page load,
  not a lost click.)
- Any other `click` is recorded, and its default left alone (a button's default is nothing, or
  submitting its form, which is the next case).
- A `submit` is recorded, and its default prevented: otherwise the browser leaves the page to post
  the form, losing it. If the submit came from a recorded click on its submit button (the event's
  `submitter`), the replayed click submits again, so the `submit` itself isn't replayed.
- `input` and `change` are recorded, and only the last for each element kept: what the user typed is
  already in the element (§7 keeps it on hydration), and replaying the last event tells the
  component, through its `onInput`, so its state matches what's on screen.

**Replay.** After each commit that hydrated something (the root, or a boundary), `DomHost`'s
`resetAfterCommit` (which runs after every commit already) goes through the queue in order. Each
record whose target is now hydrated and still in the document is dispatched again, as a new event of
the same type with the same properties (`clientX`, `key`, the modifiers; `bubbles` and `cancelable`
as the original), so the handlers `DomHost` attached run, through `flushSync` as any event's do. A
submit that wasn't a click's is replayed with `form.requestSubmit(submitter)`. A record whose target
isn't hydrated yet stays queued, and holds back the ones after it, so a sequence ("add", then
"save") isn't replayed out of order. If the page navigates or is refreshed before then, the queue is
dropped: the elements it pointed at are gone.

**Selective hydration, cheaply.** A record in a dehydrated boundary whose content has already been
swapped in (it's waiting on a row or a chunk, §6) asks for that boundary to be tried again at once,
at the sync lane rather than waiting its turn: the boundary the user is touching hydrates first.
This uses the retry dehydrated boundaries already have (`onSuspenseReady`'s callback).

**Not replayed**: `keydown` and pointer events other than clicks (shortcuts and drags make little
sense replayed later), focus (the browser's own focus stays where the user put it, and hydration
doesn't move it), and anything outside `#root`.

**Tests.** The runtime's recording rules in jsdom (each event type, links, submitters, coalesced
inputs); replay after the root hydrates and after a boundary does, in order, holding back behind an
unhydrated target; a boundary touched before it has hydrated being hydrated first; the `weft_notes`
like button and comment form used before the bootstrap has run (the harness opening the page with
its bootstrap held back, then releasing it); and a browser test clicking before a slowed bootstrap.

### 11. `useId` (phase 7.8, a follow-up)

`Hooks.useId()`: a string unique on the page, the same in the server's HTML and on hydration, for
linking elements (`htmlFor` and `id`, `aria-labelledby`, `aria-describedby`). It can't be a counter:
the server and the client render components in different orders (the server concurrently, the client
depth first, and only after the server's HTML has been streamed in pieces), so it has to come from
where the component is in the tree, which both sides agree on, because both render the same decoded
tree (§1).

**The position.** Each function component's position is its nearest function-component ancestor's
position, followed by the path from that ancestor's output down to it: one index per level, through
hosts, fragments, providers, error boundaries and arrays (an element's index among its siblings),
with a `Suspense` boundary's content and fallback told apart. Levels that only one side has are
skipped: the reconciler's own `Offscreen` fiber (between a boundary and its content) and a
fallback's wrapper fragment. A `Lazy` element is the element it resolves to, on both sides, so it
adds nothing. A component's `n`th `useId` call appends `n`.

- **On the server**, the HTML renderer's walk carries the position (as it already carries the path
  for its messages, §3), and `ServerRender.renderComponent` takes it, for `useId` to read.
- **In the reconciler**, a component mounting computes its position once, from its parent fibers'
  `index` (each fiber's position among its siblings, which `Fiber` already keeps) up to the nearest
  function component, skipping the levels above, and keeps it in its hook. A component mounted later
  on the client has a position too, unique among what's mounted, which is all an ID needs.
- **The ID** is the position, encoded compactly (base 32, separated), with a prefix: `w` by default,
  and a root's own if there are several on one page (`hydrateRoot(~idPrefix)`,
  `Page.respond( ~idPrefix)`), since each root's positions start from scratch.

**Server components** don't hydrate (their output is in the payload, as values), so their IDs only
need to be unique in the page: `useId` there could take a counter for each `Render`. That's left out
until a server component needs one; for now it fails there, as other hooks do (error 14).

**What it needs from the earlier phases**, which is why it can follow without changing them:
`renderComponent` takes an options record (contexts now, a position later) rather than positional
arguments; and the HTML renderer and the reconciler walk the same levels in the same order. That
second one is a rule for phases 7.2 and 7.3, written here so they don't diverge: neither side may
add or merge a level the other doesn't, except the two listed above.

**Tests.** Positions computed by the HTML renderer and by the reconciler agreeing over the fuzz
tests' random trees (every component's position, compared); IDs surviving a boundary that hydrates
later, a keyed list reordered after hydration (positions are fixed at mount), and a boundary
switching between fallback and content; and `weft_notes`' comment form linking its labels.

## Packages and layout

After phase 7.0 (§0), and with what phase 7 adds:

```
packages/weft_core/src/
  shared/HostConfig.res             gains `Hydratable`
  shared/Reconciler.res(i)          `MakeHydratable`, with `hydrateRoot`; hydration in the work loop
  shared/internal/Hydration.res     the cursor, claiming, mismatches, dehydrated boundaries
  shared/ServerRender.res(i)        gains `renderComponent` (client components, on the server)
  shared/Hooks.res(i)               `useSyncExternalStore(~getServerSnapshot)`; `useId` (7.8)
  testing/TestRenderer.res(i)       hydratable; `fromMarkup`
packages/weft_dom/src/
  shared/DomProps.res               the prop rules, shared by the host and the HTML renderer
  client/DomHost.res                `HostConfig.Hydratable`; event replay (7.7)
  client/Client.res(i)              gains `hydrateRoot`
  server/Html.res(i)                the HTML renderer: `renderToStream`, `renderToString`, the runtime
packages/weft_server/src/
  shared/Decoder.res(i)             today's `Client`, renamed
  shared/Rpc.res(i), RpcCodec       declaring and calling RPCs
  shared/Navigation.res(i)          `makeForServer`
  server/Render.res(i)              unchanged
  server/RpcServer.res(i)           `handler`, `router`, `respond`: from today's `Rpc`
  server/Page.res(i)                the HTML in the page: shell, rows, segments; `~html`
  client/Bootstrap.res              `hydrateRoot` when the page has HTML
packages/vite_plugin_weft/          `virtual:weft/ssr-references`; the harness's HTML
examples/weft_notes/, weft_split/   the scenarios again, over hydrated pages
```

New error codes: `weft_core` 15 (`useSyncExternalStore` without `~getServerSnapshot` on the server)
and 16 (a hydration API used with a host that can't hydrate); `weft_dom`'s first codes (it has none
yet), for the HTML renderer's refusals (a tag or attribute name that isn't one, children of a void
element, `<script>` or `<style>` content); `weft_server` 20 (`navigate` or `refresh` on the server's
page).

## Phases

Each ends green (build, check, test, typecheck, e2e), the plan updated where the implementation went
its own way, committed, pushed, and reviewed before the next.

**Phase 7.0 -- Client and server, kept apart** (§0). The `client/`, `server/`, `shared/` and
`testing/` directories; `@@weft.server` on the server-only modules, with the packages compiling
through `ppx_weft`, and a plugin test that an app's client importing one is refused; `Rpc` split
into `Rpc` and `RpcServer`; `WeftServer.Client` renamed `Decoder`; the "Where it runs" tables; the
apps and the main plan updated for the names. No new behaviour.

**Phase 7.1 -- Hooks on the server.** `ServerRender.renderComponent` (with an options record, which
§11's position joins later) and its resets; `useSyncExternalStore(~getServerSnapshot)` (and its use
during hydration, wired in 7.3); with their tests. Small, and everything after depends on it.

**Phase 7.2 -- The HTML renderer.** `DomProps`' shared rules (with `DomHost` moved onto them, its
tests unchanged), then `WeftDom.Html.renderToString`: every element kind, props, escaping, special
elements, nesting warnings. Then streaming: `renderToStream`, boundaries, markers, segments and the
swap runtime, with their tests.

**Phase 7.3 -- Hydration in the reconciler.** `HostConfig.Hydratable`, `MakeHydratable` and
`hydrateRoot`; the cursor and claiming; text; complete, pending and failed boundaries; suspending
while hydrating; mismatches and recovery; `TestRenderer`'s hydration and `fromMarkup`; the unit
tests and the fuzz test. It walks the same levels as 7.2's renderer (§11's rule, for `useId` later).
The largest phase, and the riskiest: the work loop's mount path gains a second way through every
host fiber.

**Phase 7.4 -- Hydration in the DOM.** `DomHost`'s hydration operations,
`WeftDom.Client.hydrateRoot`, the swap runtime's retry, the attribute warnings; the jsdom round
trips and the DOM fuzz test.

**Phase 7.5 -- Pages.** `Page`'s HTML (the server-side `Decoder`, the tee, the shell, rows,
segments, the failed-shell fallback, `~html`), `Navigation.makeForServer`, `Bootstrap` hydrating,
the plugin's `virtual:weft/ssr-references`; `weft_server`'s page tests and the one-process
end-to-end tests.

**Phase 7.6 -- The harness, the apps and the browser.** The harness's HTML (`openPage` applying the
page as a parser would, `hydrated`, `htmlNodes`, `warnings`, `~bootstrap=false`); `weft_notes`' and
`weft_split`'s scenarios over hydrated pages, and the new ones; the browser tests.

**Phase 7.7 -- Event replay** (§10), a follow-up: the runtime's recording, replay in
`resetAfterCommit`, the cheap selective hydration, and their tests.

**Phase 7.8 -- `useId`** (§11), a follow-up: positions on both sides, the hook, prefixes, and their
tests. Independent of 7.7; either can come first.

## Decisions

All settled in review: 3 (dehydrated boundaries, "option A"), 4 and 9 (event replay and `useId`,
designed here and built after the rest, as phases 7.7 and 7.8), and the rest as recommended.

1. **Render HTML from the payload decoded on the server** (§1), rather than from the original tree:
   server components run once, and the HTML is rendered from exactly the tree the client hydrates.
2. **Run it in the `rsc` environment**, with a server copy of the reference map, rather than a third
   `ssr` environment: Weft has one `weft_core`, so one server build and module graph will do.
3. **Dehydrated boundaries** (§6), settled: a boundary still pending when hydration reaches it keeps
   the server's HTML and hydrates once its segment is swapped in, rather than being rendered on the
   client from scratch (which would throw away HTML the server already sent, and could flash the
   client's fallback over it). Selective hydration by priority comes with event replay (§10),
   cheaply.
4. **Event replay** (§10), settled: designed now, built as phase 7.7. Until then a click on an
   element before it has hydrated is lost (links and forms still work as HTML, and the bootstrap
   loads early, so the window is short). It's additive: nothing in 7.1 to 7.6 changes for it.
5. **Mismatch policy** (§8): text patched with a warning; anything structural renders the nearest
   boundary on the client, with a warning; attributes warned about, not changed. The same recovery
   in production, without the warnings.
6. **HTML on by default**, with `Page.respond(~html=false)` per route.
7. **A failed shell falls back to today's page** (rows only, rendered on the client), with a 200,
   rather than an error page: the client may well render it, and throws the error where an
   `ErrorBoundary` can catch it if not.
8. **Hydration renders in a transition lane**, so a suspension outside every boundary waits with the
   server's HTML on screen, rather than needing a boundary.
9. **`useId`** (§11), settled: designed now, built as phase 7.8. Its one demand on the earlier
   phases is a rule for 7.2 and 7.3 (the HTML renderer and the reconciler walk the same levels), and
   an options record for `renderComponent`; with those, it doesn't change the architecture.

10. **Input typed before hydration is kept** (§7), as React does: hydration doesn't put a controlled
    `value` or `checked` back over what the user typed or ticked. Until event replay (7.7) tells the
    component, its state lags what's on screen until its next update.
11. **The HTML renderer is `weft_dom`'s**, as `WeftDom.Html`, in its `server/` (§0, §3), and the
    code is reorganized first so client and server code are told apart (phase 7.0).

## Risks

- **The reconciler's mount path gets a second branch** through every host fiber, and hydration's
  bugs are the quiet kind (a node adopted in the wrong place still renders). The fuzz tests, against
  a client render, are the main defence; they come with the code, in 7.3 and 7.4, not after.
- **The HTML parser's repairs** (verified point 2) are the classic cause of mismatches. The nesting
  warnings cover the common ones; the rest show up as structural mismatches, which recover, with a
  warning saying where.
- **Entrypoint code now runs on the server.** Module-level DOM access in an entrypoint file, or a
  render that reads `window`, crashes the server render (and only the HTML: the shell fails, and the
  page falls back to client rendering). The rule (no DOM outside handlers and effects) goes in the
  READMEs, and the shell's error names the component.
- **Doubling the payload's work on the server** (encoding, then decoding it again) is linear and in
  memory; if it ever shows in profiles, `Render` could hand the decoder its rows without the JSON
  text in between.
- **Context on the server is passed explicitly** to each component call (§2), because the renderer
  is asynchronous and `ContextImpl`'s stack is global. A component that reads a context some other
  way (a module-level variable set by a provider) would see the wrong value; nothing in Weft does.
- **Time to first byte** grows by the shell's render: the head goes out at once (so the bootstrap
  and its chunks start loading), but the body waits for everything outside every boundary. Pages
  that are slow outside their boundaries should get boundaries, as they would for streaming today.

## Out of scope

Selective hydration beyond §10's (hydrating whatever the user is about to touch, by hover or focus);
`useId` in server components (§11); RPCs called by forms without JavaScript (progressive
enhancement, which this makes possible: §8 of the server components plan leaves it for later);
static generation (rendering pages to files at build time, which `renderToString` would allow);
caching rendered HTML; CSS beyond what Vite does; hydrating a page that wasn't rendered by Weft.
