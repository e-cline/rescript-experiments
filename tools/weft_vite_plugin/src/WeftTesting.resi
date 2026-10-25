/***
ReScript bindings to the plugin's test harness (`@e-cline/weft_vite_plugin/testing`): an app's
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

/**
Changes the body of each request whose path contains `matching` (`"/_weft/rpc/notes.addComment"`),
before the server gets it, until `stopRewriting`: a client older or newer than the server, say, or a
forged request.
*/
let rewriteBodies: (app, string, string => string) => unit

let stopRewriting: app => unit

/**
The cookies the client has, by name: what the server's `Set-Cookie` headers set (and haven't
expired), sent with every request after, as a browser sends its cookies for the app's origin.
*/
let cookies: app => dict<string>

/** Forgets every cookie: the next request is a new visitor's. */
let clearCookies: app => unit

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
Opens `url` in `container`: its HTML is requested from the server and applied as the browser's
parser would, as it's delivered: the shell into `container` (which stands for `#root`), then each
inline script and segment in order, so the rows are pushed and boundaries swapped in. Once the shell
is in, `WeftServer.Bootstrap` starts, and hydrates it. In `Build` mode the build's own bootstrap does
(and a test file can open one page: move on by following links), and `container` has to be the
document's `#root`.

With `~bootstrap=false` the bootstrap waits for `startBootstrap`, as if its chunk loaded late, or
never: what the HTML shows by itself (the page's inline scripts still run). A boundary's segment goes
in the document's body, found by its id, so one page is open in a document at a time.
*/
let open_: (
  app,
  ~container: WeftDom.Dom.element,
  ~delivery: delivery=?,
  ~bootstrap: bool=?,
  string,
) => page

/** Starts the bootstrap of a page opened with `~bootstrap=false`: now, or once the shell is in. */
let startBootstrap: page => unit

/**
Closes the page (`Source` mode), as leaving it would: its root is unmounted, so its effects are
cleaned up (their intervals and subscriptions with them), and it stops following the history.
Opening another page closes the one before, so a page left open by one test can't act in the next.
*/
let closePage: page => unit

/**
Waits until the bootstrap has hydrated the page (or rendered it, if there was no HTML): it has
started, the entrypoints it needed have loaded (but those `holdLoads` holds), and the renders after
are done. A boundary still streaming hydrates later, as its content arrives, and one waiting on a
held load once it's released. Fails after `timeout` milliseconds (5000).
*/
let hydrated: (page, ~timeout: int=?) => promise<unit>

/**
What `console.error` and `console.warn` said since the page opened (until the next page opens): in a
development build, where hydration found the HTML and the client's render disagreeing.
*/
let warnings: page => array<string>

/** The requests made since the page opened (its own first), by path (with the query), in order. */
let pageRequests: page => array<string>

/**
The URL the page opened at (its path and query), or, once its HTML has come, where the server
redirected that to. (`Navigation.url` of its `navigation` says where it has got to since.)
*/
let url: page => string

/** The page's navigation (`Source` mode), once the bootstrap has started on its first payload. */
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

/** Holds entrypoint loads until `releaseLoads`: those whose file id contains `matching`. */
let holdLoads: (page, ~matching: string=?) => unit

let releaseLoads: page => unit

/** The entrypoint files loaded, in order. */
let loads: page => array<string>

/**
The stylesheets the client (or a segment's swap) added, in order: those of what rendered after the
shell, whose own are in the page's head (which the harness applies, loaded, as a browser shows
nothing before them). jsdom loads none: the harness has each "load" a task after it's added.
*/
let stylesheets: page => array<string>

/**
Holds stylesheets (they don't load) until `releaseStylesheets`: those whose URL contains `matching`
(every one, by default), so a test can see what waits for one, and that nothing shows without it.
*/
let holdStylesheets: (page, ~matching: string=?) => unit

let releaseStylesheets: page => unit

/**
The elements on the page shown without their CSS: each with a `weft_css` class whose sheet hasn't
loaded (`<tag class="...">`). It should always be empty: check it at every step.
*/
let unstyled: page => array<string>

/** How many times the entrypoint `id` (`<file>#<module path>`) has rendered. */
let renderCount: (page, string) => int

/** The nodes under the container now, to compare with later. */
type snapshot

let snapshot: page => snapshot

/** The nodes in `snapshot` no longer under the container (`tag#id`, or quoted text). */
let removedSince: (page, snapshot) => array<string>

/**
The nodes the HTML has made under the container: the shell's, and each segment's as it's swapped in,
less those the swaps took out (the fallbacks). `removedSince` it is empty once a page has hydrated
with nothing rendered again on the client.
*/
let htmlNodes: page => snapshot

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
