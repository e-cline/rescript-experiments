---
'@e-cline/weft_dom': patch
---

- `autoFocus` focuses an element rendered after the page has loaded (a dialog's field, say), once
  the commit has put it in the page: the attribute alone only works for elements there as the page
  loads.
- Hydration compares `style` values as the browser reads them back, so the same style written
  another way (`hsl(...)`, read back as `rgb(...)`; `-0%` as `0%`) isn't reported as a difference.
- New props: `ariaExpanded`, `ariaSelected`, `ariaControls`, `ariaCurrent`, `ariaHidden`,
  `ariaLive`, `ariaModal`, `ariaBusy`, `required`, `autoComplete`, `inputMode` and `maxLength`.
