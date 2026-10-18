---
'@e-cline/weft_core': patch
---

Production builds throw `WeftCore error <code>` instead of the full error messages, which only
development builds include (the README's "Error codes" section lists them). This makes the
production bundle about 0.8 KB smaller (300 B gzipped).
