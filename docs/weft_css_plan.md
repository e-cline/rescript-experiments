# Plan: CSS for Weft

Styles written in ReScript, next to the components that use them (or in modules of their own, for
shared ones), extracted into ordinary CSS files at build time, and sent to the browser only when
something on the page uses them, with no flash of unstyled content: for client components, for
server components, for server-rendered HTML streamed in pieces, and for pages and parts of pages
fetched on navigation.

```rescript
// src/client/AddToCart.res: an entrypoint
@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})
open WeftCss

module Styles = {
  let button = Css.class({
    display: InlineFlex,
    gap: Rem(0.5),
    padding: Px(8),
    color: Var(Theme.onAccent),
    background: Var(Theme.accent),
    borderRadius: Px(6),
    hover: Css.style({background: Var(Theme.accentHover)}),
    disabled: Css.style({opacity: 0.5}),
  })
}

@weft.component({kind: Entrypoint})
let make = (~sku: string) =>
  <button className=Styles.button onClick={_ => ...}> {WeftDom.Jsx.string("Add to cart")} </button>
```

```rescript
// src/server/ProductPage.res: a server component, whose styles never reach the client as code
@@jsxConfig({version: 4, module_: "WeftDom.Jsx"})
open WeftCss

let page = Css.class({display: Grid, gridTemplateColumns: Raw("2fr 1fr"), gap: Rem(2.0)})
let price = Css.class({fontSize: Rem(1.5), fontVariantNumeric: TabularNums})

@weft.component({kind: Server})
let make = async (~id) => {
  let product = await Db.product(id)
  <div className=page>
    <Gallery images=product.images />
    <p className=price> {WeftDom.Jsx.string(Money.format(product.price))} </p>
    <AddToCart sku=product.sku />
  </div>
}
```

`ProductPage`'s CSS reaches the browser because the page rendered `page` and `price`, and only then;
`AddToCart`'s, because the browser loads `AddToCart`'s code. Neither is shown before its CSS has
loaded.

## Status

Reviewed: the recommended decisions are taken (Decisions). Phase 0's spikes are done, and the design
below is corrected by what they found ("Phase 0: what the spikes found", after Phases), in Chromium,
Firefox and WebKit. Phase 1 is done (`packages/weft_css`, and the PPX's rewrite), with notes on what
it settled under "As built (phase 1)", after §2. Phase 2 is done too (the plugin's extraction,
`weftCss()` and `weft_app` on it), under "As built (phase 2)", after §3. And phase 3 (the server's
half of sending sheets: the manifest, `Render`'s `C` rows, the page's head), under "As built (phase
3)", after §4. And phase 4 (the client's half: loading sheets, rows waiting for them), under "As
built (phase 4)", after phase 3's. And phase 5 (streamed segments wait for their sheets), under "As
built (phase 5)", after §6. Phase 6 is next.

## What was checked before writing this

Against the code as `main` has it (after `weft_shop`, PR 14), and the sources named:

1. **Weft has no CSS story yet.** The plugin's `virtual:weft/assets` has `styles` (the stylesheets
   the bootstrap's chunks import, from the client manifest), and `Page` writes them as
   `<link rel="stylesheet">` in the head; entrypoint files' CSS isn't carried at all (`buildAssets`
   keeps only `closure(...).files` for them, not `css`). Both plans list CSS beyond what Vite does
   as out of scope. `weft_shop` puts a 100-line stylesheet, as a string, in every page's head
   (`examples/weft_shop/src/server/Styles.res`, through `Page.respond(~head)`).
2. **`rescript-css` (`@jvlk/rescript-css` 0.2.0) can't be used as it is**, though its API is a good
   one to follow (read at its current `main`):
   - Its Vite plugin **rewrites the compiled `.res.js` files on disk** (at `configResolved` and
     again in `transform`): it replaces each style call with its class name and adds
     `import "./Button.css"` at the top, writing the `.css` file beside it. Here the compiled output
     is committed and a clean build has to reproduce it exactly (the server components plan's
     "Things learned"), so a plugin that edits it is a non-starter.
   - It finds what to replace with **regular expressions over the compiled JavaScript**
     (`let Styles = {...}` patterns, `export {...}` lists), which is tied to the compiler's output
     format; Weft's plugin reads only directives the PPX writes, for that reason.
   - It collects CSS by **`import()`ing every compiled module of the app in Node**, with a collector
     on `globalThis`; class names are `rc_<hash of the file>_<n>`, numbered in the order the
     module's calls run. The runtime and the extraction both depend on that global collector (nested
     `hover: Css.style(...)` registers a rule in it too), so its value layer can't be reused without
     its runtime.
   - **Its CSS is attached to modules by side-effect imports**, which is what makes it work with
     Vite's CSS code-splitting, and also what makes it not work for server components: a server
     component's file is never in the client's module graph, so its stylesheet is never in the
     client build, and nothing tells the page it's needed.
   - It needs Node ≥ 24.12 (the workspace allows ≥ 22).
3. **React 19's stylesheet resources** (react.dev, `<link>`): a `<link rel="stylesheet">` with a
   `precedence` is hoisted into the head, de-duplicated by `href`, ordered by precedence (groups in
   the order first seen, later groups winning), and **the component rendering it suspends until it
   has loaded**, so the nearest `Suspense` boundary keeps its fallback (or, in a transition, the old
   content stays) until the CSS is there. In streaming SSR (from Fizz's source as I know it, not
   re-read for this plan), Fizz holds a boundary's reveal until the stylesheets it rendered have
   loaded (its completion script, `$RR`, inserts them and waits), rather than blocking the parser.
   Server components reach it with `ReactDOM.preinit(href, {as: "style", precedence})`, which Flight
   sends as a hint row.
4. **`@vitejs/plugin-rsc`** (its README): CSS imported by a server component's module, directly or
   not, is collected with `import.meta.viteRsc.loadCss(importer?)`, a React node of
   `<link precedence>`s; by default the plugin wraps every capitalized exported function of a server
   module that imports CSS in it (`rscCssTransform`, with a `filter` to opt out). A client
   reference's CSS comes with it (`onClientReference` sees `deps: {js, css}`). The unit is the
   **module graph**: what's imported, not what's rendered.
5. **Next.js's App Router** (from its behaviour as I know it; its docs didn't say, and this is worth
   confirming against its source if it matters) works the same way, per route segment: the CSS of a
   layout's or page's module graph (server and client components) is listed in the RSC payload for
   that segment and rendered as React stylesheet resources (`precedence="next"`), so a client
   navigation's new segments suspend until their CSS has loaded. **TanStack Start** (its CSS guide)
   puts the CSS of the matched routes' modules in its manifest, and notes that CSS imported from an
   async component isn't in the initial SSR links. **Remix/React Router, SvelteKit, SolidStart and
   Astro** are route- or page-graph based too; SvelteKit and Astro inline stylesheets under a size
   threshold.
6. **Compile-time CSS-in-JS**: vanilla-extract evaluates `.css.ts` files at build time (in a module
   runner) and turns them into CSS imports plus class-name exports; Linaria (wyw-in-js) evaluates
   only the slice of a file its styles depend on; StyleX and Panda extract statically and go atomic,
   one stylesheet for the whole app, whose size grows with the number of distinct declarations
   rather than components. All of them, again, are module-graph or whole-app. **Qwik** is the one
   that goes by what renders: a component's `useStyles$` registers its styles when it renders, and
   SSR writes only the rendered components' styles into the page.

So nothing here can be reused as it is. Every Vite-based option ties CSS to modules, which is right
for client components (their code is loaded, so their CSS might as well be) and wrong for this
plan's main case: server components whose output is dynamic (a CMS's blocks, a search's results),
where a module-graph rule sends the CSS for every block type the page _could_ render. What can be
reused is the shape of the answers: rescript-css's API, vanilla-extract's build-time evaluation,
React's "a boundary doesn't reveal until its stylesheets have loaded", and Qwik's "send what
rendered".

## How it works, end to end

```
compile    Button.res ──ppx_weft──► Button.res.js: Css.class(...) calls become
                                     Internal.class_("Button-button_wk3f9a", () => {...})
                                     + 'use weft css' directive

vite       scan for 'use weft css' ──► evaluate each file in a CSS module runner (Node), calling
                                       the definitions ──► one sheet per file: wk3f9a.css
           transform (client and rsc) ──► the definitions are stripped: only the names are left
           build ──► each sheet a hashed asset; the manifest: sheet id → URL, and for each
                     entrypoint file the sheets its client module graph imports

request    Render walks the tree ──► host className props and strings in entrypoint props are
                                     matched against sheet ids ──► a C row per sheet, first use;
                                     J rows name the C rows they need; E rows bring their own sheets
           Page ──► head held open until the shell is ready, then the shell's sheets as links
                    in the head; later sheets preloaded as they come; a segment's swap waits for
                    its sheets to load

browser    Decoder ──► a C row loads its sheet (a <link> in the head, once per href);
                       a J row waits for its sheets as it waits for its entrypoints
           navigation/refetch: new rows render in a transition, so nothing shows unstyled
```

Two ways for a class name to reach the DOM, and one rule for each:

- **From the server**, in the payload: a server or shared component's output, or a string handed to
  an entrypoint as a prop. The server sees it as it writes the payload, and sends the sheet with the
  rows that use it: CSS by **what rendered**.
- **From client code**: an entrypoint (or anything it imports) rendering one of its own classes,
  perhaps only after a click. That code is in the browser anyway, and its sheets come with it: CSS
  by **what's loaded**, as every Vite framework does, but per style file rather than per chunk.

Class names are constants the PPX writes (styles are static: dynamic values go through CSS
variables, §2), so there's no third way, short of building one by hand from a string.

## Design

### 1. The package: `weft_css`

A new ReScript package, `@e-cline/weft_css`, namespace `WeftCss`, depending on nothing but
`@rescript/runtime`. Its main module is `Css`, so code reads `Css.class(...)` after `open WeftCss`.
The API follows rescript-css's, so its documentation mostly applies and code ports with few changes:

| Call                                              | Gives          | CSS                                                         |
| ------------------------------------------------- | -------------- | ----------------------------------------------------------- |
| `Css.class(css)`                                  | a class name   | `.name { ... }` and its nested rules                        |
| `Css.style(css)`                                  | a `Css.t`      | none by itself: a nested block, or a fragment to reuse      |
| `Css.global(~selector, css)`                      | `unit`         | `selector { ... }`                                          |
| `Css.var(initial)`                                | a `Css.var`    | `--name: initial` on `:root`, in the declaring file's sheet |
| `Css.keyframes([Css.frame(~at, css), ...])`       | a name         | `@keyframes name { ... }`                                   |
| `Css.fontFace({...})` (later)                     | a family name  | `@font-face { ... }`                                        |
| `Css.media(~query, css)`, `supports`, `container` | a condition    | nested in the class's rule                                  |
| `Css.layerOrder([...])`, `~layer=` on the above   |                | `@layer` (§5)                                               |
| `Css.vars([(var, value)])`                        | a `style` dict | none: custom properties for `style=`, at run time           |
| `Css.cx([a, b])`, `Css.cxOpt([Some(a), None])`    | a class list   | none                                                        |

`css` is a record of optional fields, one per property, typed where it's worth it (`display`,
lengths, colours, `Var(v)`) and with `Raw(string)` everywhere as the way out; nested selectors are
fields too (`hover`, `focusVisible`, `disabled`, element names like `h2`,
`selectors: [("&[data-open]", Css.style(...))]`, `media: [...]`). Phase 1 starts with the properties
`weft_shop` uses, and grows; the property set is the bulk of the work and the least risky part
(rescript-css's `CssValue` is 2,000 lines of it), so it's done incrementally, with `Raw` covering
what's missing.

`Css.style` is `external style: t => t = "%identity"`, so a fragment (`let base = Css.style({...})`)
compiles to a plain object literal, which bundles can drop once nothing uses it (an ordinary
function would make it a call, and its module impure). `Css.var` gives an abstract `Css.var`, its
name, which `Var(v)` serializes as `var(name)`.

**Styles are static.** `Css.class`, `global`, `var`, `keyframes` and `fontFace` are allowed only in
`let` bindings at a module's top level (in any nesting of modules), and the PPX rejects them
anywhere else, with an error saying to use a CSS variable (`Css.vars`), a data attribute and a
`selectors` rule, or one class per variant. That's what lets every class have a name at compile
time, and every sheet be a file.

**Without the PPX**, `Css.class` and the others throw when called ("weft_css: this file wasn't
compiled with ppx_weft"). They're called at module level, so the first import fails, at once; and
the Vite plugin checks `ppx-flags`, as it already does for `@weft.component`.

### 2. The PPX (`ppx_weft`)

`ppx_weft` gains the style calls. In a file that has any:

```rescript
// src/client/AddToCart.res, written
module Styles = {
  let button = Css.class({display: InlineFlex, hover: Css.style({background: "#115e59"})})
}

// what the compiler then sees
@@directive("'use weft css'")
module Styles = {
  let button = Css.Internal.class_("AddToCart-Styles-button_wk3f9a", () => {
    display: InlineFlex,
    hover: Css.style({background: "#115e59"}),
  })
}
```

which bsc compiles, every time, to the shape the plugin rewrites (§3):

```js
'use weft css';
let button = Css$WeftCss.Internal.class_('AddToCart-Styles-button_wk3f9a', () => ({
  display: 'InlineFlex',
  hover: {background: '#115e59'},
}));
```

- **The name** is readable, then the file's **sheet id**: `w` and six base-36 digits of a hash
  (32-bit FNV-1a, modulo 36⁶) of the file's id
  (`<package name>/<source path from the package root>`, the same id entrypoints use, so it's the
  same in every checkout). The plugin checks that no two files' sheet ids collide. The readable part
  is the file's module name and the binding's path, made into a CSS identifier; it's unique within
  the file, since bindings at one path are. Compiled output is committed and the same in development
  and production, so names can't be shortened for production by the PPX; the plugin could rewrite
  them later (Follow-ups).
- **The definition becomes a thunk.** At run time, in the browser and on the server, `class_` just
  returns the name: definitions are never evaluated, so nothing of `Css`'s value layer runs or, once
  the plugin strips the thunks (§3), is bundled. Extraction calls them.
- `var`, `keyframes` and `fontFace` get names the same way (`--Theme-accent_wk3f9a`), and `global`
  an index in the file. A value naming another file's var or keyframes (`Var(Theme.accent)`) is a
  string constant by then, so evaluating one file's definitions needs the other file's _names_, not
  its definitions: the other file is imported as any module is, but its thunks aren't called.
- The call is recognized by its path's last two parts (`Css.class`, `WeftCss.Css.class`); a module
  alias (`module C = Css`) isn't followed, and gets the run-time error above. The PPX is untyped, so
  that's the best it can do, and it fails loudly rather than silently.

- A style call anywhere else (in a function, a conditional, a nested `Css.class` inside a
  definition) is a compile error at the call, naming the alternatives (§1).

`'use weft css'` is how the plugin finds files with styles, as `'use weft entrypoint'` is for
entrypoints (§3). A file can be any kind (server, entrypoint, shared) and have styles too, so the
directive goes alongside whichever of the others the file gets (the spike only handled a file with
neither).

**As built (phase 1).**

- **Keywords are `@unboxed` variants** whose constructors are `@as` their CSS keyword, with a
  `Raw(string)` catch-all (`InlineFlex` is the string `"inline-flex"` at run time), so serializing
  one is the identity, and constructor names needn't kebab-case into the keyword (`Nowrap` for
  `nowrap`). An unboxed variant can only have one string payload, so `display` has no `Var`:
  `Raw("var(...)")` does it. Lengths and colours are ordinary variants, serialized by a `switch`.
- **The serializer is explicit**, a line per property in the order `Css.t` declares its fields
  (`Serialize.declarations`), rather than walking the runtime object, whose key order a spread
  changes. Selectors nest as rescript-css's do (`&` is the parent, no `&` is a descendant, lists are
  crossed); at-rules wrap their block's rules.
- **`Extract` groups registrations by the sheet id their names end in**, so the collector is one
  list for everything that ran while recording (a file imported by another records once, whoever
  imports it first). Per sheet: variables on `:root` and globals in `weft.base`, classes and
  keyframes in `weft.components`, any other `~layer` after those, each in declaration order; and the
  sheet's dependencies, from the other sheet ids in its text. It throws for a definition that throws
  (naming it), a name registered twice, and a name with no sheet id.
- **What the PPX writes** compiles positionally: `Internal.class_(name, layer, () => ...)` and
  `Internal.global_(name, selector, layer, () => ...)`, with `undefined` for an absent layer.
  Globals are named `<Module>-global<n>`. A nested style call is checked for before anything else,
  so its error is the "static" one even in a file with no `rescript.json`; the missing
  `rescript.json` error says `Css.class:` rather than `@weft.component:`.
- **The hash, twice**: OCaml hashes the file id's bytes, so `SheetId` hashes its UTF-8 encoding
  (`TextEncoder`), not UTF-16 code units; a fixture under `fixtures/größe/` pins the two together.
  bsc compiles `x >>> 0` to `x` (a no-op in its int model), so the unsigned value is made in floats.
- **Left for later**: `Css.fontFace` and `registerProperty` (nothing uses them yet), and
  `Css.layerOrder`, which is the page's to declare (phase 3).

### 3. Extraction (the Vite plugin)

The `weft` plugin gains the CSS work. (Rather than a separate plugin: delivery needs the payload and
the manifest, which are `weft`'s. A client-only app gets a smaller `weftCss()` export, §8.)

**Finding style files.** The scan that finds entrypoint files also collects files with
`'use weft css'`, from the app's sources and its ReScript dependencies' (so a component library's
styles work), and computes each one's file id and sheet id, checking them against the names in its
`class_` calls.

**Evaluating them.** A **CSS module runner**, a Vite environment of the plugin's own (`weft_css`:
environment names may only have letters, digits, `$` and `_`; Node, resolving as the client does,
conditions included, so `Common.Env.isDev` is the same), imports each style file with a collector
installed; each `class_`, `global` and so on records its name and thunk, and the plugin calls the
thunks and serializes the results, file by file, into CSS text. One **sheet per style file**, with
its globals, vars, keyframes and font faces, and its classes in the order they're declared.

Evaluating a file runs its top level and its imports' (not their thunks). That's already a
requirement of a server-rendered Weft app: server files run in `rsc`, and every entrypoint file,
with what it imports, is imported on the server for SSR (`virtual:weft/ssr-references`). Client
modules that touch `window` at load time would break both; Weft's own don't (`WeftDom.Jsx` loads
without a DOM). The runner is separate from `rsc` so extraction never shares state with request
handling, and runs in builds as well as in development (`createRunnableDevEnvironment`, as the
plugin's dev server does today). In the spike, every one of `weft_shop`'s and `weft_notes`'
component files, server and client, evaluated in such a runner with no DOM (45 files in about 250
ms). What failed were **entry modules**: the server entry (it imports `virtual:weft/assets`) and
`weft_app`'s `Main` (it renders into `document` when loaded). The runner only imports style files
(and what they import), so an entry module matters only if it has styles itself; extraction then
fails with the file and the error, saying to move the styles to a module of their own. Slicing files
down to what their styles need, as wyw-in-js does, is the fallback if top-level side effects turn
out to be a problem in practice (Risks).

**Stripping.** In every environment's `transform`, a style file's `class_(name, thunk)` calls are
replaced by the name itself, a string literal, using Vite's parser (the calls are the PPX's, in a
fixed shape, but the plugin uses a real AST, not patterns), and the directive is blanked as the
others are. With no calls left, the module's top level is pure, and bundles tree-shake `Css`'s value
layer away; the server doesn't need it either.

**Sheets as files.** Each sheet is a CSS module whose content the plugin supplies, imported with
`?url` (`virtual:weft/css/<sheet id>.css?url`), which runs it through Vite's CSS pipeline (PostCSS
or Lightning CSS, minification and prefixing, `url()` assets) and, in a build, emits it as a hashed
asset of its own, with a manifest entry: not merged into chunks' CSS, because the same sheet is
needed from two directions (§4) and must be one URL to be loaded once. The plugin resolves the id to
a **path-like** id (`<root>/node_modules/.weft-css/<sheet id>.css`, with no file there) and loads
its content: a `\0`-prefixed virtual id breaks Vite's CSS plugin, which imports the module again as
`…?transform-only` and can't find it. (Both found in the spike.)

**The manifest** (in `virtual:weft/assets`, built from the client build):

- `sheets`: sheet id → URL (in development, the dev server's URL for the virtual module);
- `entrypoints`: each entrypoint file's chunks, as now, and also its **sheets**: those of every
  style file in its client module graph (in a build, from the chunks' module ids; in development,
  from the client environment's module graph, or the scan's own import graph of compiled files);
- `styles`: the bootstrap's own sheets, as now.

**As built (phase 2).** In `tools/weft_vite_plugin/src/internal/`: `css.ts` (sheet modules,
stripping, the `Extractor`), `cssPlugin.ts` (the plugin `weft()` includes and `weftCss()` is), and
the scan's sheet ids (`scan.ts`).

- **Recording is per copy of `weft_css`, not on `globalThis`.** The runner shares the process with a
  dev server's `rsc` environment, which may render a request (and so run style files' top levels)
  while an extraction is recording. The runner has its own copy of `weft_css` (`noExternal`), the
  plugin calls `Extract` through it, and only that runner's files reach it. (Inside `Css`, the
  recording is a flag and an array: the keyword types' `None` shadows `option`'s.)
- **The runner is a Vite server of the plugin's own** (no config file, no watcher), whose `weft_css`
  environment is runnable, in builds as in development. A build extracts every style file at
  `buildStart` (once, for both environments) and closes it; a dev server extracts on the first
  request for a sheet and keeps it, and when ReScript rewrites a style file, drops that file from
  the runner (`evaluatedModules.invalidateModule`) and imports it again, which records only it (its
  imports have run already). An app with no style files never starts it, so it needn't have
  `weft_css`.
- **An extraction error names the file imported, which may not be the one that threw** (a file the
  style file imports): the message says "importing it (or a file it imports) threw".
- **Sheets resolve to one path however they're asked for**: `virtual:weft/css/<id>.css`, the path,
  and the dev server's URL for it (`/node_modules/.weft-css/<id>.css`), so a sheet is one module,
  and a dev edit invalidates the one the page has.
- **Stripping** replaces a style call with its name and a global with `void 0`, blanking the rest of
  the call in place, through Vite's `parseAst`. The CSS plugin runs before `weft()`'s own, and
  blanks only `'use weft css'`, leaving the others for it.
- **`weftCss()`'s files import their sheets** (`import "virtual:weft/css/<id>.css"`, on the line the
  directive was), in client environments only. `weft()`'s import nothing yet: the manifest of
  sheets, and the pages linking them, are phase 3.
- **Tests**: `css.test.ts` (resolving, stripping in place), the scan's (sheet ids, a name with
  another id, two files with one), `weftCss.test.ts` (on the new `styled` fixture: a build, its
  sheets with the entry's and a lazy chunk's CSS, no definitions or serializer in the JavaScript, a
  definition that throws, a file needing the browser, a missing PPX; a dev server serving a stripped
  file and its sheet, and extracting a rewritten file again), and the `basic` build's (no definition
  in either bundle).
- **`weft_app`** moved its inline `<style>` into `src/Styles.res`: the build's CSS is 0.58 kB, and
  its JavaScript has the class names and nothing of `weft_css` but `cx`.

### 4. Which CSS a payload needs

**Payload rows.** A new row, `C`, a stylesheet:
`{"id": "wk3f9a", "href": "/assets/wk3f9a-1c2d.css"}`, one per sheet per stream, like `E`. A `J` row
that needs sheets says which: its value is wrapped as `["$C", [3, 4], value]` (a literal `"$C"`
can't occur, since strings starting with `$` are escaped). An `E` row lists its file's sheets
(`{"id": "...", "css": [3, 4]}`), whose `C` rows go before it.

**On the server, `Render` finds them as it encodes.** It's given a way from sheet id to href (`Page`
passes the manifest's; without one, no CSS rows, as in today's tests), and while encoding a row:

- each host element's `className` is split into tokens, and a token ending in a known sheet id (`_w`
  and six base-36 digits) names that sheet;
- every string in an entrypoint's props, at any depth (including promises' rows), is checked the
  same way, so a class a server component hands to an entrypoint
  (`<Card className=Styles.featured />`, `~tone=Styles.cool`) brings its sheet;
- each entrypoint brings its file's sheets from the manifest (its `E` row lists them);
- sheets whose `var`s or `keyframes` another sheet's rules use come too: extraction records a
  sheet's dependencies on other sheets (names carry their sheet id, so that's a parse of the CSS
  text), and the manifest has them.

The row's sheets not yet sent become `C` rows written just before it, and the row lists all it
needs. It costs a tokenize per `className` and a suffix check per prop string, against a set; the
benchmarks will say whether that's noticeable (Risks).

That's precise to what rendered: a CMS page with three of its forty block types sends three blocks'
sheets, and a search that returns no sale items doesn't send the sale badge's. It's also blind to
how the output was produced (server component, shared component, conditional, loop), which is the
point.

**In the browser, the decoder waits for them.** A `C` row loads its sheet through `WeftCss.Sheets`:
a `<link rel="stylesheet">` appended to the head, or the one already there for that `href` (the
first page's, from the server, or an earlier navigation's), its `load` (or `error`: a failed sheet
mustn't hide content forever, as in React) settling a `Deferred`. A `J` row isn't turned into
elements until its sheets have loaded, exactly as it waits today for its entrypoints' modules
(Flight's "blocked" rows); an `E` row's module counts as loaded once its sheets are too. So:

- **on navigation and refetch**, the new tree renders in a transition, and a boundary whose rows
  wait for CSS keeps the old content (or its fallback, if it's new) until they're in: nothing shows
  unstyled, and the old screen stays as long as it would for slow data;
- **an entrypoint's chunk and its sheets load in parallel**, both started by the `E` row, rather
  than the sheets after the JavaScript;
- sheets are never removed once loaded (as in React): styles are static, so a sheet that's no longer
  used is harmless, and taking it away could unstyle something still on screen.

**Client code's own sheets.** Each style module, as transformed for the client, also registers its
sheet when it's evaluated (`Sheets.use(href)`), which inserts the link if the server hasn't already.
For an entrypoint that's a no-op (its `E` row brought its sheets); it's what covers code loaded some
other way (a `Weft.Lazy` around an `import()` in a client-only app), and development.

**As built (phase 3).** The server's half: what to send, and the first page's head. The client's
(loading the sheets, rows waiting for them) is phase 4.

- **`Render`'s scan moved here from phase 4**: the head can only link the shell's sheets if the
  server knows them, which is the scan. `Render.toStream(~styles)` takes the manifest's sheets
  (`Render.styles`: each sheet's `href` and `dependencies`, and each entrypoint file's sheets); each
  row collects what it needs (host `className`s, strings in entrypoint props, an entrypoint's own
  sheets, and dependencies, before what needs them, with cycles allowed), writes a `C` row for each
  the first time, and wraps its value as `["$C", [rows], value]`. Without `styles` nothing changes,
  so every payload test from before still holds.
- **An `E` row doesn't list its sheets**, as first planned: the `J` row with the entrypoint lists
  them, as it does its classes'. One rule for the decoder to follow (a row waits for the `C` rows it
  names), rather than two.
- **The decoder** settles a `C` row with its URL and unwraps `$C`; it doesn't wait yet (phase 4).
- **`Page`** writes the head at once but for its end (`headStart`), and, once the shell's ready, the
  stylesheet links for the `C` rows written so far, the entrypoints' `modulepreload`s (which used to
  be at the start of the body), and `</head><body>`. Payload responses (navigation) get `C` rows
  too. A page without HTML (`html=false`) closes its head at once, as before: its sheets are the
  client's to load. RPC responses (`RpcServer`) don't send sheets yet: an element an RPC returns is
  styled only by what's already loaded (phase 4).
- **The layer order is in every sheet**, `@layer weft.base, weft.components;` first
  (`Extract.layerOrder`), not in the page's head: the first stylesheet to name a layer fixes its
  place, whichever that is, and `weftCss()` apps, with no page of Weft's, need it as much.
- **The manifest** (`virtual:weft/assets`) gains `sheets` (id → `{href, dependencies}`) and
  `entrypointSheets` (file id → sheet ids). A build emits every sheet from a chunk of its own,
  `virtual:weft/sheets`, importing each with `?url` (emitted with `preserveSignature: 'strict'`, or
  its unused export, and with it every `?url` import, is dropped); only an app with style files has
  it. Each sheet's file is found in the client manifest by its path's end (its key is a relative
  path outside the root). In development, `href` is the dev server's URL for the sheet, which it
  serves as `text/css` to a `<link>`.
- **Entrypoint sheets come from the compiled files' static imports** (`imports.ts`), walked from
  each entrypoint file through the scanned packages (`./X.res.js`, `<package>/...`), not from the
  bundle: the same in development and builds, and known before either has built anything. Dynamic
  imports aren't followed.
- **Checked end to end** on `weft_split`, with a style added for the check (not committed): `/`
  linked the home page's sheet and `Counter`'s (an entrypoint on it) in its head, before the shell;
  `/other`'s payload sent only `Counter`'s, the home page's motto not being on it.
- **Tests**: `weft_server`'s `Sheets_test` (the rows for classes rendered, dependencies first and
  once; a branch not rendered isn't sent; entrypoint props and code; a boundary's row; the wrapper;
  decoding the same elements with sheets as without; the page's head held, then the shell's links);
  the plugin's (`imports.test.ts`; the manifest in development, with the sheet served as CSS, and in
  a build, with the sheets emitted and the server's assets naming them).

**As built (phase 4).** The client's half: loading the sheets, and rows waiting for them.

- **`WeftCss.Sheets`** (`weft_css/src/client/`): `load(href)` adds a `<link rel="stylesheet">` to
  the head, once per document, or adopts the one the document has (the server's, for the shell,
  found by its `href` attribute); `isLoaded(href)` says whether it has. A link whose `sheet` is set
  has loaded (its `load` may have fired before anyone listened, as phase 0 found); otherwise its
  `load` or `error` settles it: a sheet that fails shows what waits for it unstyled, rather than
  never. The states live on `globalThis.__weftCss` (`{loaded, promise}` by URL), for phase 5's
  inline runtime to share. Without a document (on the server), every sheet has loaded.
- **The decoder** takes `~loadSheet` (by default the document's: `None` if the sheet has loaded, or
  a promise that settles once it has), starts loading a `C` row's sheet as the row arrives, and
  holds back a `J` row until the sheets it names have loaded, as it does until its entrypoints have.
  A sheet that has loaded already is `None`, not a resolved promise, so a row needing only those
  decodes at once: a payload that has fully arrived still never suspends (the shell's sheets, linked
  in the head, have loaded by the time the bootstrap runs).
- **Navigation and refetching** need nothing more: their payloads render in a transition, so a root
  row waiting for its sheets keeps the old page on screen, and a boundary's row keeps its old
  content (or, if it's new, its fallback).
- **Sheets are appended in the order they're needed**, not base sheets first (§5): with every rule
  in a layer, and every sheet stating the layers' order, the order of links only matters within a
  layer, where §5 already says not to rely on it.
- **Not done**: style modules registering their own sheets when the client evaluates them (§4's
  "client code's own sheets"). Entrypoints' sheets come with the rows that use them, which covers
  every Weft app so far; code loaded some other way (a `Weft.Lazy` around an `import()`, in a
  `weft()` app) would have its classes unstyled. A follow-up, with RPC responses' sheets.
- **The harness** (`loadStylesheets`, in `testing.ts`): jsdom loads no stylesheets, so the harness
  has each one added to the head fire `load` a task later, and records it
  (`WeftTesting.stylesheets`). Phase 5 puts loading under a test's control.
- **Checked in browsers**: `weft_split` again, with a style added for the check (not committed),
  navigating from `/other` to `/` (whose motto's sheet `/other` never needed) with CSS slowed by 800
  ms. In Chromium, Firefox and WebKit the motto was never on screen without its colour (first shown
  about 880 ms in; the old page stayed until then). With the decoder made not to wait, as a control,
  Chromium showed it unstyled in every frame from 82 ms on.
- **Tests**: `weft_css`'s `Sheets_test` (in jsdom: one link per URL, loading, failing, adopting the
  page's links, loaded or not, the shared states) and `SheetsWithoutDocument_test`; `weft_server`'s
  `Sheets_test` (the root held back until its sheets load, nothing held for sheets already loaded, a
  boundary keeping its fallback until its content's sheet loads, a navigation keeping the old page
  until the new one's sheets load); the plugin's `stylesheets.test.ts`.

### 5. Order

One sheet per file, loaded in the order the page first needs them, means **the order of rules from
different files can differ from page to page** (the same is true of CSS Modules with Vite's code
splitting, and of any per-route scheme). Two classes from different files setting the same property
on the same element is then a coin toss. The rules:

- **Global rules and vars come first.** A sheet with `global`, `var`, `fontFace` or
  `registerProperty` rules is a _base_ sheet; `Sheets` inserts base sheets before every component
  sheet in the head, as React does for a lower `precedence`, and the server's links are written
  base-first too.
- **Everything is in cascade layers**, by default `@layer weft.base, weft.components`, declared at
  the top of every sheet (as built: see phase 3's notes), so whichever loads first, the order holds.
  An app's own unlayered CSS then overrides `weft_css`'s, which is what a hand-written stylesheet
  usually wants; `~layer=` puts a rule in another layer, and `Css.layerOrder` declares more
  (rescript-css's API).
- **Within a layer, across files, there's no order**: compose in one class
  (`Css.class({...Base.button, color: ...})`, a record spread of a `Css.style` fragment) rather than
  stacking two classes that conflict. A development-build check for it, at extraction (two classes,
  different files, same layer, overlapping properties, used together in a `Css.cx`), is a follow-up
  if it turns out to bite.

### 6. The first page: head, shell and segments

Today the head goes out at once, then `#root` with the shell once it's ready. CSS changes that a
little:

1. **The head is held open until the shell is ready.** Its start goes out at once, as now (charset,
   the event runtime, title, the layer order, the bootstrap's script and preloads, the bootstrap's
   own sheets), so the browser starts on the JavaScript while the server renders; then, once the
   shell is ready, a `<link rel="stylesheet">` for every sheet the rows written so far need (base
   sheets first), `</head><body>`, and `#root` with the shell. Links in the head are render-blocking
   by the HTML spec, so **the shell never paints unstyled**, with no reliance on how browsers treat
   stylesheets in the body. (The bootstrap's `async` script may run before `#root` exists; it
   already waits for it, since phase 7.6.)
2. **Later sheets are preloaded as soon as they're known**: a `C` row written after the shell is
   preceded by `<link rel="preload" as="style" href>`, as an `E` row is by its `modulepreload`s
   today, so the download starts while the boundary's content is still rendering.
3. **A segment waits for its sheets.** `$weftSwap(n)` (the inline runtime, `Html.runtime`) becomes
   `$weftSwap(n, [hrefs])`: it inserts any of those sheets not yet in the head (in order, base
   first), and swaps the content in once they've loaded, as React's `$RR` does. Waiting in the swap,
   rather than writing `<link>`s into the body before the segment, means one slow sheet doesn't stop
   the parser, and so doesn't hold up other boundaries' segments behind it. The page gives a segment
   every sheet requested since the shell that isn't known to be loaded; being exact per segment
   (which rows its HTML was rendered from) is a refinement if the over-waiting shows.
4. **Inline script and the bootstrap share one registry.** The runtime keeps `self.__weftCss` (href
   → loaded or a promise), and `Sheets` adopts it, together with the links already in the document
   (read by `href`; one whose `sheet` is set has loaded, and its `load` event may have been missed),
   so a sheet is never loaded twice, whichever side asked first.
5. **Hydration** needs nothing new: the shell's sheets are loaded before it painted, and a segment's
   are loaded before it's swapped in and, after that, hydrated. The bootstrap's decoder sees the
   same `C` rows, finds their links loaded, and doesn't wait.

`html=false` pages get the same head (minus the shell), and the client loads sheets from the rows.

**As built (phase 5).**

- **A segment's sheets are exactly its markup's**, not "every sheet requested since the shell", as
  first planned: `WeftDom.Html.render(~stylesheetsOf)` hands each segment's HTML, once rendered, to
  a function from `Page` that finds the sheet ids its class names end in (`SheetId.inText`) and
  gives their URLs, dependencies first. Classes an entrypoint renders are in the markup too, so its
  code's sheets come only if the server rendered something of them. A segment needing none is
  written as before, `$weftSwap(n)`.
- **The runtime** gains `$weftCss(href)`, a sheet's state on `self.__weftCss` (`{loaded, promise}`,
  the shape `WeftCss.Sheets` keeps): from the page's link for it (loaded if its `sheet` is set) or a
  new one in the head. `$weftSwap(n, hrefs)` waits for those not loaded, then swaps. The client's
  `Sheets` and the runtime use the same states, so a sheet has one link, whichever asked first. The
  runtime has no `<` in it, so nothing reading the page's scripts can take one for a tag.
- **Preloads**: a `C` row written after the shell is preceded by `<link rel="preload" as="style">`,
  so the download starts when the server learns of the sheet, not when the segment arrives.
- **The server's decoder never waits for a sheet** (`Page` gives it `~loadSheet=_ => None`): it has
  no document to show anything in. Found when a jsdom test, with the server and the client in one
  process, made the server's decoder wait for a link that the client side was meant to load.
- **Hydration** needed nothing new: the swap tells hydration only once it has swapped, and the
  boundary's rows wait for the same sheets through the same states.
- **Tier 2**: the harness applies the head's stylesheet links to its document as loaded (a browser
  shows nothing before them), loads the others a task after they're added unless a test holds them
  (`holdStylesheets`, `releaseStylesheets`), and reports elements with a `weft_css` class whose
  sheet hasn't loaded (`unstyled`, which should always be empty). `weft_shop`'s tests use them in
  phase 7.
- **Checked in browsers**: `weft_split`'s home page with a boundary added for the check (not
  committed) whose content arrives after 1 s and has a sheet of its own, slowed by 1.5 s. Chromium,
  Firefox and WebKit never showed it without its colour (first shown at about 2.55 s: the preload
  started the download when the row was written), and it hydrated. With the swap rewritten in flight
  not to wait, as a control, Chromium showed it unstyled for 91 frames from 1.0 s.
- **Tests**: `weft_dom`'s `HtmlStylesheets_test` (the swap naming its sheets, waiting for them,
  adding their links, an error counting as loaded, the page's loaded links and the client's loading
  ones shared); `weft_server`'s (the page's preload and swap; in jsdom, a boundary swapped in and
  hydrated once its sheet loads, from one link); the plugin's `stylesheets.test.ts` (head sheets as
  pieces, applied loaded; others loaded, held, released; `unstyled`).

### 7. Development

- ReScript writes a `.res.js`; if it's a style file, the plugin re-evaluates it (invalidating it in
  the CSS runner) and compares the sheet. Names come from binding paths, not definitions, so editing
  a definition changes only the CSS: the plugin sends a `weft:css` HMR event, and `Sheets` swaps
  that link's `href` (with a `?t=` stamp) in place, keeping all state. No reload, no refetch.
- Adding, renaming or removing a style changes the JavaScript too, so the existing rules apply (a
  client module: reload; a server one: refetch), and the CSS event goes with it.
- A file gaining or losing `'use weft css'` redoes the scan, as entrypoints do.
- Development pages link sheets by the dev server's URLs; the manifest's per-entrypoint sheets come
  from the module graph, so the first page in development is as unflashy as in production (the usual
  development FOUC of Vite frameworks comes from CSS injected by JavaScript; nothing here is).

### 8. Client-only apps

`weft_app` and other apps without a server have none of §4–6 to hook into, and don't need it:
`weftCss()` (from `@e-cline/weft_vite_plugin`) does §3's scan, evaluation and stripping, and has
each style module import its sheet (`import "virtual:weft/css/<id>.css"`), so Vite's own CSS code
splitting applies: chunk CSS, loaded before a dynamic import resolves. That's the module-graph rule,
which for client code is the right one (§ How it works).

## Testing

As the other plans: unit tests per package, the plugin's build and dev tests, tier 2 (the harness,
in jsdom) and tier 3 (Playwright, against the build).

- **`ppx_weft`** (`tools/ppx/weft_tests`): snapshot tests of the rewrite (names, thunks, the
  directive, nested modules), and the errors: a style call in a function, in a non-`let` position,
  `global` outside module level.
- **`weft_css`**: serialization of each property kind, nesting (`&`, selector lists, media inside
  selectors), vars and keyframes, layers; and `Sheets` in jsdom (dedupe by `href`, adopting existing
  links and `__weftCss`, base-before-component insertion, an `error` settling, the HMR swap).
- **The plugin**: scan fixtures (ids, collisions, a dependency's style file), extraction of a
  fixture app (each sheet's text, pinned), stripping (the bundle has no `Css.def`, and no `CssValue`
  code), the manifest's entrypoint sheets in a build and in dev, a dev edit producing a `weft:css`
  event and no reload.
- **`weft_server`**: `Render` writing `C` rows only for classes rendered (a server component
  rendering one of two branches; a class passed to an entrypoint as a prop; a class only an
  entrypoint uses, through its `E` row; a var dependency), once per stream, before the row; the
  `Decoder` blocking a row on a sheet (with a fake `Sheets`), and an error unblocking it; `Page`
  holding the head until the shell, the shell's links in it, preloads after it, `$weftSwap`'s sheet
  list.
- **`weft_dom`**: the swap runtime waiting for sheets in jsdom (links whose `load` the test fires).
- **Tier 2**: the harness applying a page piece by piece and checking, at each step, that every
  element in the visible DOM with a weft class has its sheet loaded. jsdom doesn't load CSS, so the
  harness tracks `link` elements and fires `load` itself, under the test's control (as it gates
  latency today), which also lets a test hold one sheet back and see a segment wait.
- **Tier 3, the real check for flashes**: `weft_shop`, moved from its inlined stylesheet to
  `weft_css` (phase 6), gets a test page script (in its test-only routes) recording, with a
  `MutationObserver` and `getComputedStyle`, any element with a weft class that was ever displayed
  while its sheet wasn't applied, across the first page, streamed boundaries, navigations and a
  refetch, with the gated server slowing CSS responses. It must record none. Another test counts the
  sheets a page requests against the blocks it rendered.

## Packages and layout

```
packages/weft_css/                 @e-cline/weft_css, namespace WeftCss
  src/shared/Css.res(i)            the API (§1), Css.Internal (what the PPX writes)
  src/shared/Value.res(i)          typed values: lengths, colours, keywords, Raw
  src/shared/Serialize.res(i)      definitions to CSS text (run by the extraction)
  src/client/Sheets.res(i)         loading, dedupe, order, HMR
  tests/
tools/ppx/weft/                    the style calls (§2)
tools/weft_vite_plugin/            scan, CSS runner, stripping, sheets, manifest; weftCss() (§3, §8)
packages/weft_server/              Payload's C rows, Render's scan, Decoder's waiting, Page's head
packages/weft_dom/                 Html.runtime's $weftSwap(n, hrefs)
examples/weft_shop/                moved to weft_css; the flash test
```

## Phases

Each ends green and reviewed before the next, as before; one PR for all of them unless review says
otherwise.

| Phase | What                                                                                    |
| ----- | --------------------------------------------------------------------------------------- |
| 0     | Spikes (below); this plan corrected by what they found                                  |
| 1     | `weft_css`: the API and serializer for `weft_shop`'s properties; `ppx_weft`'s rewrite   |
| 2     | The plugin: scan, CSS runner, stripping, one sheet per file; `weftCss()` and `weft_app` |
| 3     | Sheets in the manifest, entrypoint sheets; `C` rows, `Render`'s scan; `Page`'s head     |
| 4     | `Decoder` waiting, `Sheets`; navigation and refetch                                     |
| 5     | Streaming: preloads, `$weftSwap` waiting, the shared registry, hydration; tier 2 checks |
| 6     | Development: re-extraction and the `weft:css` HMR swap                                  |
| 7     | `weft_shop` on `weft_css`; the tier 3 flash test; docs and READMEs                      |

## Phase 0: what the spikes found

Scripts in the session's scratchpad, not committed, against ReScript 12.3.1, the workspace's Vite+
(`vite-plus-core` 1.3.0) and Playwright 1.63. The design above already includes what's corrected.

1. **ReScript.** A `css` record of optional fields, recursive through nested blocks (`hover?: t`,
   `selectors?: array<(string, t)>`), type-checks, with type-directed constructors (`Var` in both
   lengths and colours) and record spread of fragments. Errors are good
   (`The field colour does not belong to type Css.t … Did you mean color?`). `class` is fine as a
   function name (bsc writes it `$$class`). **Editor completion** (`rescript-editor-analysis`)
   completes field names, variant constructors and nested fields inside `Css.class({...})` and
   `Css.style({...})`, and nothing at all inside `%css.class({...})`, which parses but is opaque to
   it: Decision 3 holds. Correction: `Css.style` as an ordinary function made every fragment a call;
   as `%identity` it's a literal.
2. **The PPX.** A copy of `ppx_weft` with the rewrite (about 80 lines of OCaml) handles bindings at
   any module depth (`Button-Styles-Nested-x_wnscs2w`), writes the directive, and rejects a call in
   a function with a compile error at the call. bsc's output is the fixed shape in §2. Still to do
   in phase 1: the directive alongside `'use weft server'` and `'use weft entrypoint'`, files with
   `@weft.component` and the JSX transform, and interfaces (`let button: string` needs nothing).
3. **The runner.** As in §3: all component files of two apps evaluate in a separate Node runner (45
   files in about 250 ms, the dev server's start 15 ms), and entry modules don't, which is a rule to
   state, not a design change. The environment's name can't have a `-`.
4. **Vite.** `.css?url` of a module the plugin supplies gives a minified, prefixed
   (`-webkit-user-select`), layer-preserving, content-hashed asset of its own, with `url()`s
   rewritten (a small image inlined) and an entry in the build manifest; chunks list their modules
   in `generateBundle` (`chunk.moduleIds`), which is what entrypoints' sheets are computed from.
   Correction: the id must be path-like, not `\0`-prefixed (§3).
5. **Browsers**: Chromium, Firefox 155 and WebKit 26.6 (Playwright's builds), with a probe checking
   every animation frame for content shown without its styles, and negative controls that do flash
   (49 to 97 unstyled frames each), so the probe catches it. In all three:
   - **a head held open** for 1.5 s, then a stylesheet that takes 0.8 s, then `#root`: no unstyled
     frame, first paint at 2.3 s;
   - **a segment swapped in only once its sheet, appended to the head, has loaded**: no unstyled
     frame (swapped 1.1 s in); swapping without waiting flashes;
   - **a `<link>` that loaded before anyone listened** has `link.sheet` set, and a `load` listener
     added then never fires, so `Sheets` must check `sheet` first, as planned.

   WebKit needed real content to show anything: with a few words on the page it holds the first
   paint until the document ends (so its first run's negative controls didn't flash either), and
   with a paragraph it paints, and flashes, as the others do. It also never flashed a stylesheet a
   script appended to the head before the first paint (the `/a-naive` control), which the design
   doesn't rely on.

   **When the bootstrap runs**, a second script (`boot.mjs`): in Chromium and Firefox the `async`
   module script runs within a few milliseconds, while the head is still open or the body is still
   streaming. **WebKit runs it only when the parser next gets bytes**, or at the document's end: on
   a page that sends nothing for 3 s after `#root`, at 3 s, whether the head was held open or not,
   with a stylesheet or not; on one that writes a row every 200 ms, at once. (A classic `async`
   script runs at once in all three; an inline module script waits for the parser everywhere, as the
   spec says.) So holding the head open doesn't change when Safari hydrates. Weft's pages have this
   already: a page whose shell is out, with a slow boundary and no rows in between, hydrates in
   Safari only once the boundary's segment arrives. That's outside this plan; it's a follow-up
   (Follow-ups 7).

## Decisions

Settled in review: each recommendation below was taken.

1. **Our own `weft_css` rather than rescript-css, or a fork of it.** _Recommended: our own_, with
   rescript-css's API names, so docs and code carry over. Its extraction (rewriting committed
   output, regexes over compiled JavaScript, module-level CSS imports) is exactly what has to
   change, and its value layer is tied to its runtime's global collector. A fork would keep the
   2,000 lines of typed values but replace everything else; porting the value types as needed is
   less to maintain. Worth asking its author whether a shared value package is of interest.
2. **One sheet per style file.** _Recommended_ for v1: it's the unit that both directions (§4) can
   share and that makes "what rendered" precise. Many small requests are the cost: HTTP/2 makes them
   cheap, and two follow-ups reduce them (inlining small sheets into the HTML; grouping sheets that
   always load together, such as one entrypoint's). Alternatives: per class (most precise, many more
   rules to track, inline `<style>` only), or per chunk (Vite's default, which over-sends for server
   components).
3. **Plain calls (`Css.class(...)`) recognized by the PPX**, rather than an extension point
   (`%css.class(...)`) or an attribute (`@weft.css let button = {...}`). _Recommended: plain calls_:
   it's rescript-css's API, editor completion works inside it (to confirm in phase 0), and a missing
   PPX still fails at once (§1). The cost is that aliases of `Css` aren't followed.
4. **What rendered, by scanning class names** (§4), rather than tracking which server modules ran
   (`plugin-rsc`'s `loadCss`, Next's segments). _Recommended_: it's precise for dynamic output,
   needs no module graph on the server, and covers classes that cross into entrypoints as props. It
   relies on class names having a recognizable shape, which the PPX guarantees.
5. **Layers by default** (§5). _Recommended_, so app CSS overrides and order between base and
   component rules is fixed. The alternative is unlayered rules and a documented order.
6. **Holding the head open until the shell is ready** (§6), rather than writing the shell's links in
   the body before `#root` (render-blocking in today's browsers, but not by the spec) or delaying
   the whole head. _Recommended_: spec-backed, and the JavaScript still starts at once.

## Risks

- **Evaluating style files at build time runs their top level.** A module that does I/O or touches
  `window` when loaded would fail extraction. Mitigation: it already fails SSR; the error names the
  file; slicing (wyw-in-js's approach) is the fallback.
- **Order across sheets** (§5) is the classic code-splitting CSS bug, made a little more likely by
  per-file sheets. Mitigation: layers, base-first insertion, composition by spread, documentation,
  and a dev check if needed.
- **Scanning cost in `Render`**, on every `className` and entrypoint prop string. Mitigation: a
  suffix check before any lookup; the benchmarks include a large list page before and after.
- **Many small requests** on pages with many style files. Mitigation: measure on `weft_shop`;
  inlining and grouping follow-ups.
- **A sheet that never loads** (network, a 404 after a deploy) must not hide content forever:
  `error` settles like `load`, and the content shows unstyled, as with React.
- **Holding the head open** delays nothing the browser could use (the scripts are already in it),
  but a slow shell now also delays `</head>`: anything an app adds to `~head` that it expected to
  apply early still does, since it's in the head's start.

## Follow-ups

1. **Inline small sheets** in the first page's HTML (`<style data-href>`, adopted by `Sheets`), as
   SvelteKit and Astro do. Small.
2. **Group sheets** that always load together (an entrypoint's, a layout's) into one asset. Medium.
3. **Short class names in production**, rewritten by the plugin in both builds. Medium.
4. **Skip sheets the client already has** on navigation: the client sends what it has loaded (a
   header), and the server leaves out those `C` rows. Small, once measured to matter.
5. **An atomic mode** (StyleX-like), for apps that would rather ship one cached sheet. Large.
6. **The cross-file conflict check** (§5). Medium.
7. **Hydrating sooner in Safari** (not CSS: found in phase 0). WebKit runs the `async` bootstrap
   only when the parser gets more bytes, so a streamed page that goes quiet after its shell hydrates
   only once something more arrives. The page could write a tiny keep-alive (an empty comment) soon
   after the shell, or load the bootstrap as a classic `async` script that imports the module.
   Small, with a WebKit browser test.

## Out of scope

CSS written as `.css` files and imported by ReScript modules (Vite's own handling still works for
client code, as today, but isn't extended to server components); runtime-generated styles; Sass and
other preprocessors beyond what Vite's pipeline already does to the extracted CSS.
