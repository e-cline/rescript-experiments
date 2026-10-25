/*** The entry: renders into the page when it loads, so it has no styles itself (see the plan's §3). */

module Dom = WeftDom.Dom

let container = Dom.createElement(Dom.document, "div")
Dom.appendChild(Dom.body(Dom.document), Dom.elementToNode(container))
let root = WeftDom.Client.createRoot(container)
WeftDom.Client.render(root, <Card title="hello" />)

// `Later` comes in a chunk of its own, after the first render.
import(Later.view)->Promise.thenResolve(view => WeftDom.Client.render(root, view()))->ignore
