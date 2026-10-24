/***
The browser's start: reads the first page's payload from the rows its HTML carries (`Page`),
renders it into `#root`, and goes on from there with a `Navigation` page: links call `navigate`,
which pushes the URL onto the history, and going back or forward loads the URL it goes to.

The Vite plugin's default bootstrap calls `start`, with its `loadModule` and `onRefresh` (which
refetches the page when a file only the server has changes in development).
*/

/**
The payload a page's inline scripts push onto `target.__weft` (`self`, in a browser), as a stream:
the rows pushed before this is called, then each as it's pushed, until the end (`null`).
*/
let rows: {..} => Streams.t

/**
Starts the page: decodes the rows on `self` into `container` (by default `#root`), hydrating the
server's HTML there if the page has it (`data-weft-html` on the container), as the client
`loadModule` and `fetch` (by default `Decoder.webFetch`) make. `url` is the page's (by default the
location's path and query). Resolves with the page, once its first payload has rendered.

Aborting `signal` stops the page: its root is unmounted (effects cleaned up, intervals and
subscriptions with them) and it no longer follows the history. A browser has no need of it (leaving
the page stops it); a test that opens one page after another in the same document does.
*/
let start: (
  ~loadModule: Decoder.loadModule,
  ~fetch: Decoder.fetch=?,
  ~container: WeftDom.Dom.element=?,
  ~url: string=?,
  ~onRefresh: (unit => unit) => unit=?,
  ~signal: Streams.Signal.t=?,
  unit,
) => promise<Navigation.t>

/**
What the Vite plugin's default bootstrap calls, with its `loadModule` and `onRefresh`: `start`, on a
page that has a `#root` (and nothing, on one that doesn't). Run while the page is still being parsed
(its script is `async`) before `#root` has arrived, it starts once it has.
*/
let main: (Decoder.loadModule, (unit => unit) => unit) => unit
