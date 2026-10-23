---
'@e-cline/weft': patch
---

Hydration: `Reconciler.MakeHydratable(Host)`, for a host implementing `HostConfig.Hydratable`, gives
`hydrateRoot(container, element)`, a root whose first render adopts the content already in the
container (a server's HTML) instead of creating nodes. A `Suspense` boundary whose content hadn't
arrived stays as the server rendered it until it does; one whose content suspends while hydrating
keeps the server's content; a mismatch or an error renders the nearest boundary (or the root) on the
client. `useSyncExternalStore` reads its server snapshot while hydrating. `TestRenderer` can hydrate
markup (`hydrate`, `resolveBoundary`, `failBoundary`, `toMarkup`).
