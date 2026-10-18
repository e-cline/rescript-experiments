---
'@e-cline/fiber': patch
---

Checking that hooks are called in the same order on every render now happens in development only, as
in React, which takes the check and its messages out of production bundles (about 0.5 KB, 170 B
gzipped).
