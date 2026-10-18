---
'@e-cline/weft_dom': patch
---

New package: the DOM renderer for `@e-cline/weft_core`. `Client.createRoot`/`render` render
components into the page through `WeftDom.Jsx`, whose host tags take `DomProps.props` (attributes,
`value`/`checked` as properties, a `style` dict, `on*` listeners, `ref`). Updates made in event
handlers render before the event returns, controlled inputs keep their prop's value, and focus
survives reorders. `Portal` renders children into another element, and content a `Suspense` boundary
hides gets `display: none`. `Elements.jsxs` marks written-out children as static, so
`@e-cline/weft_core`'s missing-key warning skips them.
