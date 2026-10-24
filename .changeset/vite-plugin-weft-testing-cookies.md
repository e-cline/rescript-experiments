---
'@e-cline/weft_vite_plugin': patch
---

The test harness keeps cookies, as a browser does for the app's origin: what the server's
`Set-Cookie` headers set is sent with every request after, until it expires (`cookies`,
`clearCookies`). Opening a page closes the one before it (`closePage`): its root is unmounted, so
its intervals, subscriptions and history listener stop, and can't act in the next test.
