/***
Rendering part of a component's output somewhere else: into another container of the same renderer
(a dialog layer at the end of the page, say), while it stays in the component's place in the tree.

Context, error boundaries and effects work across a portal as if its children were where the portal
is. Only the host nodes go elsewhere. Renderers wrap this with their own container type
(`TestRenderer.portal`, `WeftDom.Portal`).
*/

/**
`children`, rendered into `container`, which must be the renderer's container type. Its existing
children are left alone; the portal's are added after them.
*/
let create: (~container: 'container, ~key: string=?, Element.t) => Element.t
