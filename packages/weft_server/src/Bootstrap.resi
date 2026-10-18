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
Starts the page: decodes the rows on `self` into `container` (by default `#root`), as the client
`loadModule` and `fetch` (by default `Client.webFetch`) make. `url` is the page's (by default the
location's path and query). Resolves with the page, once its first payload has rendered.
*/
let start: (
  ~loadModule: Client.loadModule,
  ~fetch: Client.fetch=?,
  ~container: WeftDom.Dom.element=?,
  ~url: string=?,
  ~onRefresh: (unit => unit) => unit=?,
  unit,
) => promise<Navigation.t>

/**
What the Vite plugin's default bootstrap calls, with its `loadModule` and `onRefresh`: `start`, on a
page that has a `#root` (and nothing, on one that doesn't).
*/
let main: (Client.loadModule, (unit => unit) => unit) => unit
