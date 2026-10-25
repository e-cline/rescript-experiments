---
'@e-cline/weft_dom': patch
---

`Html.render ~stylesheetsOf`: a streamed segment's swap waits for the stylesheets its markup needs.
A segment inside one still waiting runs once that one is in. A new `dataId` prop writes `data-id`,
for tests to find an element by.
