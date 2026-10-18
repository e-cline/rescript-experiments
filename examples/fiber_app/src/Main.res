@@jsxConfig({version: 4, module_: "FiberDom.Jsx"})

/***
The page's entry point (loaded by `index.html`): renders `App` into `#app`.
*/

module Dom = FiberDom.Dom

switch Nullable.toOption(Dom.document->Dom.body->Dom.querySelector("#app")) {
| Some(container) => FiberDom.Client.createRoot(container)->FiberDom.Client.render(<App />)
| None => Console.error("fiber_app: no #app element to render into")
}
