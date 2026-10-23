/***
The page's entry point (loaded by `index.html`): renders `App` into `#app`.
*/

module Dom = WeftDom.Dom

switch Nullable.toOption(Dom.document->Dom.body->Dom.querySelector("#app")) {
| Some(container) => WeftDom.Client.createRoot(container)->WeftDom.Client.render(<App />)
| None => Console.error("weft_app: no #app element to render into")
}
