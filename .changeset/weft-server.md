---
'@e-cline/weft_server': patch
'@e-cline/weft_core': patch
---

New package: `weft_server`, server components for Weft. `Render.toStream` renders a tree, server
components and all, into a streamed payload; `Client` decodes it into elements as it arrives,
loading entrypoints on demand, so a refetched payload patches the screen in place. `Page` streams a
first request's HTML with the payload in it (or answers with the bare payload), `Bootstrap` starts
the browser on it, `Navigation` fetches pages and renders them in place, and `useRefetchable`
fetches part of a page again by itself. `Rpc` is Weft RPCs: functions with an ID of their own,
declared in shared code (with a codec for the request, from `Rpc.Codec`, and checks before it's
sent) and handled on the server by a router, which reads requests as plain JSON, never through the
payload decoder; responses are payloads, so they can carry elements and promises. `Testing` connects
the server and the client in one process, for tests.

`weft_core`: `Deferred`, a promise whose outcome `Hooks.use` and `Lazy` elements can read the moment
it's settled; `ServerRender.suspendedOn`; `JsxCore.isStaticList` and `markStaticList`; and a
rejected `Lazy` element now throws from its own position, so an `ErrorBoundary` whose child it is
catches it.
