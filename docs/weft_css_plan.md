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
it settled under "As built (phase 1)", after §2. Phase 2 is next.

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

### 5. Order

One sheet per file, loaded in the order the page first needs them, means **the order of rules from
different files can differ from page to page** (the same is true of CSS Modules with Vite's code
splitting, and of any per-route scheme). Two classes from different files setting the same property
on the same element is then a coin toss. The rules:

- **Global rules and vars come first.** A sheet with `global`, `var`, `fontFace` or
  `registerProperty` rules is a _base_ sheet; `Sheets` inserts base sheets before every component
  sheet in the head, as React does for a lower `precedence`, and the server's links are written
  base-first too.
- **Everything is in cascade layers**, by default `@layer weft.base, weft.components`, declared once
  in the page's head (before any sheet). An app's own unlayered CSS then overrides `weft_css`'s,
  which is what a hand-written stylesheet usually wants; `~layer=` puts a rule in another layer, and
  `Css.layerOrder` declares more (rescript-css's API).
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
| 3     | Sheets in the manifest; `Page`'s head held open, the shell's links; entrypoint sheets   |
| 4     | `C` rows, `Render`'s scan, `Decoder` waiting, `Sheets`; navigation and refetch          |
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
