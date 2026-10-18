@@jsxConfig({version: 4, module_: "Weft.Jsx"})

/***
The page's entry point (loaded by `index.html`): renders `App` into `#app`.
*/

module Dom = Weft.Dom

switch Nullable.toOption(Dom.document->Dom.body->Dom.querySelector("#app")) {
| Some(container) => Weft.Client.createRoot(container)->Weft.Client.render(<App />)
| None => Console.error("weft_app: no #app element to render into")
}
