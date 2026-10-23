/***
The smallest useful app, for `vp run size`: one component with one piece of state, rendered into the
page. What it bundles is the floor every app pays for the reconciler and the DOM renderer.
*/

module Dom = WeftDom.Dom
module Jsx = WeftDom.Jsx

module Counter = {
  @weft.component
  let make = () => {
    let (count, setCount) = Weft.Hooks.useState(() => 0)
    <button onClick={_ => setCount(count => count + 1)}> {Jsx.int(count)} </button>
  }
}

switch Nullable.toOption(Dom.document->Dom.body->Dom.querySelector("#app")) {
| Some(container) => WeftDom.Client.createRoot(container)->WeftDom.Client.render(<Counter />)
| None => ()
}
