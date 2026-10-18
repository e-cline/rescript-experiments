/***
ReScript bindings to the plugin's test harness (`@e-cline/vite_plugin_weft/testing`): an app's
server in a worker thread (its own realm, with no DOM), and its pages opened in the test's jsdom,
with the bootstrap, entrypoints and DOM renderer the browser would have, and the server's responses
handed over when the test says.

```rescript
let app = await WeftTesting.start(~root=packageRoot)
let page = app->WeftTesting.open_(~container, ~delivery=Manual, "/notes/1")
page->WeftTesting.deliver->ignore                 // hand the client the next chunk
await page->WeftTesting.settle                    // deliver everything, finish loads and renders
let _ = await app->WeftTesting.callServer("tests/FakeDbControl.res.js", "release", [JSON.String("comments:1")])
await page->WeftTesting.navigate("/notes/2")      // through the page's own navigation
```

The test's Vite config has to use the weft plugin (an app's own `vite.config.ts` does), with the
`jsdom` test environment.
*/

/** The app: its server, in a worker. */
type app

/** Where the server's code comes from: the sources (through Vite), or a build. */
type mode = Source | Build

/** Starts the app at `root` (its `vite.config.ts` and `rescript.json`). */
let start: (~root: string, ~mode: mode=?, ~buildDir: string=?) => promise<app>

/** Stops the server and its Vite server. */
let close: app => promise<unit>

/**
Calls `name` in the server's module `file` (a path from the root), with `args`, in the worker: the
same module instance the app's server uses. Its result has to be cloneable.
*/
let callServer: (app, string, string, array<JSON.t>) => promise<JSON.t>

/** Every request the client has made, by path (with the query), in order. */
let requests: app => array<string>

/** How the server's responses reach the client. */
type delivery =
  /** As they're sent. */
  | Immediate
  /** One chunk per `deliver`. */
  | Manual
  /** Cut into pieces of at most this many bytes. */
  | EveryBytes(int)

/** A page open in the test's DOM. */
type page

/**
Opens `url` in `container`: its HTML is requested from the server, the rows in it are pushed as its
inline scripts would push them, and `WeftServer.Bootstrap` starts on them. In `Build` mode the
build's own bootstrap does (and a test file can open one page: move on by following links), and
`container` has to be the document's `#root`.
*/
let open_: (app, ~container: WeftDom.Dom.element, ~delivery: delivery=?, string) => page

/** The requests made since the page opened (its own first), by path (with the query), in order. */
let pageRequests: page => array<string>

/** The page's navigation (`Source` mode), once its first payload has rendered. */
let navigation: page => promise<WeftServer.Navigation.t>

/** The HTML the page came in, with the rows taken out, once it has all arrived. */
let shell: page => promise<string>

/** Hands the client the next chunk the server sent. Whether there was one. */
let deliver: page => bool

/**
Delivers everything, and waits until things are quiet: nothing to deliver, no load or request under
way, and the DOM unchanged for a while. (A page streams for as long as the server has something to
send: `waitFor` what's expected to happen.)
*/
let settle: page => promise<unit>

/**
Waits until `predicate` holds, delivering what arrives (unless delivery is `Manual`). Fails after
`timeout` milliseconds (5000 by default), saying what the page shows.
*/
let waitFor: (page, ~timeout: int=?, unit => bool) => promise<unit>

/** Waits a few turns of the event loop, delivering nothing. */
let idle: page => promise<unit>

/** Changes how responses are delivered from now on. */
let setDelivery: (page, delivery) => unit

/** Navigates to `url`, through the page's navigation. Resolves once it has rendered (or was replaced). */
let navigate: (page, string) => promise<unit>

/** Fetches the page again. */
let refresh: page => promise<unit>

/** Refetches the frame `name`, as `useFrame(name).refetch()` would. */
let refetchFrame: (page, ~url: string=?, string) => promise<unit>

/** Whether the frame `name` is pending. */
let framePending: (page, string) => promise<bool>

/** Holds entrypoint loads until `releaseLoads`: those whose file id contains `matching`. */
let holdLoads: (page, ~matching: string=?) => unit

let releaseLoads: page => unit

/** The entrypoint files loaded, in order. */
let loads: page => array<string>

/** How many times the entrypoint `id` (`<file>#<module path>`) has rendered. */
let renderCount: (page, string) => int

/** The nodes under the container now, to compare with later. */
type snapshot

let snapshot: page => snapshot

/** The nodes in `snapshot` no longer under the container (`tag#id`, or quoted text). */
let removedSince: (page, snapshot) => array<string>

/** The container's HTML. */
let html: page => string

/** Whether anything under the container matches `selector`. */
let has: (page, string) => bool

/** The first element under the container matching `selector`. */
let query: (page, string) => option<WeftDom.Dom.element>

/** The text of the first element matching `selector`. */
let textOf: (page, string) => option<string>

/** Clicks the first element matching `selector` (throws if there's none). */
let click: (page, string) => unit

/** Types `value` into the first element matching `selector`, as an `input` event. */
let input: (page, string, string) => unit
