@@jsxConfig({version: 4, module_: "ResFiberDom.Jsx"})

/***
The smallest useful app, for `vp run size`: one component with one piece of state, rendered into the
page. What it bundles is the floor every app pays for the reconciler and the DOM renderer.
*/

module Dom = ResFiberDom.Dom
module Jsx = ResFiberDom.Jsx

module Counter = {
  @jsx.component
  let make = () => {
    let (count, setCount) = ResFiber.Hooks.useState(() => 0)
    <button onClick={_ => setCount(count => count + 1)}> {Jsx.int(count)} </button>
  }
}

switch Nullable.toOption(Dom.document->Dom.body->Dom.querySelector("#app")) {
| Some(container) =>
  ResFiberDom.Client.createRoot(container)->ResFiberDom.Client.render(<Counter />)
| None => ()
}
