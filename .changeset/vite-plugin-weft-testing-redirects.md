---
'@e-cline/weft_vite_plugin': patch
---

The test harness's `fetch` follows redirects on the app's origin as a browser's does (a 303, or a
POST's 301 or 302, with a `GET`; at most 20; `redirect: 'manual'` and `'error'` respected), and its
responses say where they ended up (`url`, `redirected`); a redirect to another origin fails. A page
opened at a URL that redirects is at the URL it led to (`WeftTesting.url`), and payloads report it
to `Navigation`, as in a browser.
