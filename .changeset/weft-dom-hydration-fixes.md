---
'@e-cline/weft_dom': patch
---

Fixes:

- A `select`'s `value` now picks its option once the option is there, when the option is added in a
  later render than the value.
- `Html` writes a newline after `<pre>` and `<listing>`, which the parser drops, so content starting
  with one hydrates without a mismatch.
- `Html` writes `\r` as `&#13;`, in text and attributes, so the parser doesn't turn it into `\n` and
  hydration doesn't report a mismatch.
