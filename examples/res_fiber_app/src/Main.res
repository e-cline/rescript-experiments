@@jsxConfig({version: 4, module_: "ResFiberDom.Jsx"})

/***
The page's entry point (loaded by `index.html`): renders `App` into `#app`.
*/

module Dom = ResFiberDom.Dom

switch Nullable.toOption(Dom.document->Dom.body->Dom.querySelector("#app")) {
| Some(container) => ResFiberDom.Client.createRoot(container)->ResFiberDom.Client.render(<App />)
| None => Console.error("res_fiber_app: no #app element to render into")
}
