---
'@e-cline/res_fiber': patch
---

The internal records (fibers, roots, hooks, updates, effects, contexts, scheduler tasks) compile to
short JavaScript property names, which a minifier can't shorten itself. This makes the production
bundle about 4 KB smaller (400 B gzipped). Elements' `elementType` is now the `type` property in
JavaScript; the ReScript field names are unchanged.
